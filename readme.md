# LlamaBarn

LlamaBarn is a tiny menu bar app for running local LLMs.

<br>

![LlamaBarn](https://github.com/user-attachments/assets/a3cc6916-9f3a-41e2-b2ad-11e8e13c73d4)

<br>

## Install

Install with `brew install --cask llamabarn` or download from [Releases](https://github.com/ggml-org/LlamaBarn/releases).

## How it works

LlamaBarn runs a local server at `http://localhost:2276/v1`.

- **Install models** — from the built-in catalog
- **Connect any app** — chat UIs, editors, CLI tools, scripts
- **Models load when requested** — and unload when idle

## Features

- **Small footprint** — 12 MB native macOS app
- **Zero configuration** — models are auto-configured with optimal settings for your Mac
- **Smart model catalog** — shows what fits your Mac, with quantized fallbacks for what doesn't
- **Built on llama.cpp** — from the GGML org, developed alongside llama.cpp

## Use with

- **Chat UIs** — Chatbox, Open WebUI
- **Editors** — VS Code, Zed, Xcode
- **Editor extensions** — Cline, Continue
- **CLI tools** — OpenCode, Claude Code
- **Custom scripts** — curl, AI SDK, any OpenAI-compatible client

Or use the built-in WebUI at `http://localhost:2276`.

## API examples

```sh
# list installed models
curl http://localhost:2276/v1/models
```

```sh
# chat with Gemma 3 4B (assuming it's installed)
curl http://localhost:2276/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "gemma-3-4b", "messages": [{"role": "user", "content": "Hello"}]}'
```

Replace `gemma-3-4b` with any model ID from `http://localhost:2276/v1/models`.

See complete API reference in `llama-server` [docs](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#api-endpoints).

## Experimental settings

**Expose to network** — By default, the server is only accessible from your Mac (`localhost`). This option allows connections from other devices on your local network. Only enable this if you understand the security risks.

```sh
# bind to all interfaces (0.0.0.0)
defaults write app.llamabarn.LlamaBarn exposeToNetwork -bool YES

# or bind to a specific IP (e.g., for Tailscale)
defaults write app.llamabarn.LlamaBarn exposeToNetwork -string "100.x.x.x"

# disable (default)
defaults delete app.llamabarn.LlamaBarn exposeToNetwork
```

## Roadmap

- [ ] Support for adding models outside the built-in catalog
- [ ] Support for loading multiple models at the same time
- [ ] Support for multiple configurations per model (e.g., multiple context lengths)
