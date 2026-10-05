#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 /path/to/generated/appcast.xml" >&2
  exit 1
fi

# Publish only after the signed app archive is available at its enclosure URL.
xmllint --noout --nonet "$1"
hf buckets cp "$1" hf://buckets/ggml-org/install.sh/llama-macos/appcast.xml
