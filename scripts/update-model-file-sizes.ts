#!/usr/bin/env -S deno run --allow-read --allow-write --allow-net

/*
 * Refreshes the byte-sized `fileSize` literals in ModelCatalog.swift to match the real Hugging
 * Face assets. For each `ModelBuild`, we gather the primary file plus shard URLs, fetch the
 * repository tree once from the Hugging Face API to read authoritative sizes, then rewrite the
 * Swift literals with underscore-separated values. Accurate sizes keep disk-space checks and
 * memory estimates honest without manual edits.
 */

// Load the catalog so we can parse existing model definitions and rewrite file sizes.
const catalogPath = new URL("../LlamaBarn/ModelCatalog/ModelCatalog.swift", import.meta.url);
const catalogText = await Deno.readTextFile(catalogPath);

interface BuildInfo {
  id: string;
  repoId: string;
  paths: string[];
}

// Split a llama.cpp-style resolve URL into the Hugging Face repo id and the file path we care about.
function parseDownloadUrl(raw: string): { repoId: string; path: string } {
  const url = new URL(raw);
  const parts = url.pathname.split("/").filter(Boolean);
  const resolveIndex = parts.indexOf("resolve");
  if (resolveIndex === -1 || resolveIndex + 2 >= parts.length) {
    throw new Error(`Unsupported download url format: ${raw}`);
  }
  const repoId = `${parts[0]}/${parts[1]}`;
  const pathParts = parts.slice(resolveIndex + 2);
  const path = pathParts.join("/");
  return { repoId, path };
}

const builds: BuildInfo[] = [];
const lines = catalogText.split("\n");
let current: BuildInfo | null = null;
let capturingAdditional = false;
let pendingDownloadUrl = false;

for (const line of lines) {
  // Each `ModelBuild` block defines a catalog entry; capture its metadata until we hit `serverArgs`.
  if (line.includes("ModelBuild(")) {
    current = { id: "", repoId: "", paths: [] };
    capturingAdditional = false;
    pendingDownloadUrl = false;
    continue;
  }
  if (!current) {
    continue;
  }

  // Grab the build id to use as the replacement anchor later.
  const idMatch = line.match(/id:\s*"([^"]+)"/);
  if (idMatch) {
    current.id = idMatch[1];
  }

  if (line.includes("downloadUrl:")) {
    // The URL literal lives on the next line; flag the next iteration to parse it.
    pendingDownloadUrl = true;
    continue;
  }

  if (pendingDownloadUrl) {
    const urlMatch = line.match(/"(https:[^"]+)"/);
    if (urlMatch) {
      const { repoId, path } = parseDownloadUrl(urlMatch[1]);
      current.repoId = repoId;
      current.paths.push(path);
      pendingDownloadUrl = false;
    }
    continue;
  }

  if (line.includes("additionalParts:")) {
    // Capture shard URLs, if present; otherwise, skip the block when the literal is `nil`.
    capturingAdditional = !line.includes("nil");
    continue;
  }

  if (capturingAdditional) {
    const urlMatch = line.match(/"(https:[^"]+)"/);
    if (urlMatch) {
      const { repoId, path } = parseDownloadUrl(urlMatch[1]);
      if (!current.repoId) {
        current.repoId = repoId;
      }
      current.paths.push(path);
    }
    if (line.includes("]")) {
      capturingAdditional = false;
    }
    continue;
  }

  if (line.includes("serverArgs:")) {
    if (!current.id || !current.repoId || current.paths.length === 0) {
      console.warn(`Skipping build due to missing data: id=${current.id}`);
    } else {
      builds.push(current);
    }
    current = null;
    capturingAdditional = false;
    pendingDownloadUrl = false;
  }
}

if (builds.length === 0) {
  console.error("No builds parsed from catalog.");
  Deno.exit(1);
}

// Collect the set of file paths we need per repo so we can fetch each tree only once.
const repoToPaths = new Map<string, Set<string>>();
for (const build of builds) {
  let set = repoToPaths.get(build.repoId);
  if (!set) {
    set = new Set();
    repoToPaths.set(build.repoId, set);
  }
  for (const path of build.paths) {
    set.add(path);
  }
}

const repoData = new Map<string, Map<string, number>>();
// Pull size metadata for each repo via the HF tree API; prefer real size, fall back to LFS info.
for (const [repoId] of repoToPaths) {
  const url = `https://huggingface.co/api/models/${repoId}/tree/main?recursive=1`;
  const response = await fetch(url);
  if (!response.ok) {
    console.error(`Failed to fetch tree for ${repoId}: ${response.status}`);
    Deno.exit(1);
  }
  const payload: Array<{ path: string; size?: number; lfs?: { size?: number } }> = await response.json();
  const map = new Map<string, number>();
  for (const entry of payload) {
    if (!entry.path) continue;
    const size = entry.size ?? entry.lfs?.size;
    if (typeof size === "number") {
      map.set(entry.path, size);
    }
  }
  repoData.set(repoId, map);
}

// Sum the size of every part that belongs to a given build so we can replace the catalog literal.
const buildSizes = new Map<string, number>();
for (const build of builds) {
  const repoMap = repoData.get(build.repoId);
  if (!repoMap) {
    console.error(`Missing repo data for ${build.repoId}`);
    Deno.exit(1);
  }
  let total = 0;
  for (const path of build.paths) {
    const size = repoMap.get(path);
    if (typeof size !== "number") {
      console.error(`Missing size for ${build.repoId}/${path}`);
      Deno.exit(1);
    }
    total += size;
  }
  buildSizes.set(build.id, total);
}

function escapeRegex(str: string): string {
  return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function formatFileSize(value: number): string {
  return value.toString().replace(/\B(?=(\d{3})+(?!\d))/g, "_");
}

let updatedText = catalogText;
for (const build of builds) {
  const size = buildSizes.get(build.id);
  if (typeof size !== "number") continue;
  const pattern = new RegExp(`(id:\\s*"${escapeRegex(build.id)}"[\\s\\S]*?fileSize:\\s*)([0-9_]+)`, "m");
  if (!pattern.test(updatedText)) {
    console.error(`Could not locate fileSize for build ${build.id}`);
    Deno.exit(1);
  }
  updatedText = updatedText.replace(pattern, `$1${formatFileSize(size)}`);
}

await Deno.writeTextFile(catalogPath, updatedText);

console.log(`Updated file sizes for ${buildSizes.size} builds.`);
