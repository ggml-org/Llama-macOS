# Llama

Llama is a macOS menu bar app for running local LLMs.

[Watch a 2-minute intro](https://www.youtube.com/watch?v=7AieF7rZUTc) 📽️

<br>

![Llama](https://github.com/user-attachments/assets/df78f9ee-bb1d-4883-bf08-44371b0cd58a)

<br>

## Install

```sh
brew install --cask llama-app
```

Or download from [Releases](https://github.com/ggml-org/Llama-macOS/releases).

## How it works

Llama runs a local server at `http://localhost:8080/v1`.

- **Install models** — from the recommended list or Hugging Face
- **Connect any app** — chat UIs, editors, CLI tools, scripts
- **Models load when requested** — and unload when idle

## Features

- **100% local** — Models run on your device; no data leaves your Mac
- **Small footprint** — `4 MB` native macOS app
- **Zero configuration** — models are auto-configured with optimal settings for your Mac
- **Recommended for your Mac** — suggests models sized to fit your hardware; browse the full catalog at [llama.app](https://llama.app)
- **Standard storage** — models live in the Hugging Face cache (`~/.cache/huggingface/hub`), shared with `llama.cpp` and other HF-aware tools
- **Built on llama.cpp** — from the GGML org, developed alongside llama.cpp

## Works with

Llama works with any OpenAI-compatible client.

- **Chat UIs** — Chatbox, Open WebUI, BoltAI ([instructions](https://github.com/ggml-org/Llama-macOS/discussions/40))
- **Editors** — VS Code, Zed, Xcode ([instructions](https://github.com/ggml-org/Llama-macOS/discussions/43))
- **Editor extensions** — Cline, Continue
- **CLI tools** — OpenCode ([instructions](https://github.com/ggml-org/Llama-macOS/discussions/44)), Claude Code ([instructions](https://github.com/ggml-org/Llama-macOS/discussions/45))
- **Custom scripts** — curl, AI SDK, etc.

You can also use the built-in WebUI at http://localhost:8080 while Llama is running.

## API examples

```sh
# list installed models
curl http://localhost:8080/v1/models
```

```sh
# chat with Gemma 3 4B (assuming it's installed)
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "gemma-3-4b", "messages": [{"role": "user", "content": "Hello"}]}'
```

Replace `gemma-3-4b` with any model ID from `http://localhost:8080/v1/models`.

See complete API reference in the llama.cpp server [docs](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#api-endpoints).

## Experimental settings

**Expose to network** — By default, the server is only accessible from your Mac (`localhost`). This option allows connections from other devices on your local network. Only enable this if you understand the security risks.

```sh
# bind to all interfaces (0.0.0.0)
defaults write app.llama.Llama exposeToNetwork -bool YES

# or bind to a specific IP (e.g., for Tailscale)
defaults write app.llama.Llama exposeToNetwork -string "100.x.x.x"

# disable (default)
defaults delete app.llama.Llama exposeToNetwork
```

## Roadmap

- [ ] Support for loading multiple models at the same time
- [ ] Support for multiple configurations per model (e.g., multiple context lengths)
