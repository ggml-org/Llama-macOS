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

When you start Llama, it runs a local server at `http://localhost:8080/v1`.

If you have llama.cpp installed, Llama uses it. Otherwise, it installs a prebuilt binary for your Mac. Models you've already installed via llama.cpp show up in the app automatically. You can install any GGUF model from Hugging Face, and Llama also recommends models that fit your Mac's hardware.

You can chat with any model in the built-in WebUI, connect other apps (coding agents, chat UIs, editors), or use the API directly. Models load when requested and unload when idle, so they don't take up memory when not in use.

## Features

- **100% local** — Models run on your Mac; no data ever leaves it
- **Small footprint** — `4 MB` native macOS app
- **Zero configuration** — models are auto-configured with optimal settings for your Mac
- **Model recommendations** — a built-in list of models your Mac can run, installable in one click
- **Standard storage** — models live in the Hugging Face cache, shared with `llama.cpp` and other tools
- **Built on llama.cpp** — from the GGML org, developed alongside llama.cpp

## Example requests

List installed models:

```sh
curl http://localhost:8080/v1/models
```

Send a message to a model:

```sh
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ggml-org/gpt-oss-20b-GGUF:MXFP4",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

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

