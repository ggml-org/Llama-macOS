# Llama

Llama is a macOS menu bar app for running local LLMs.

[Watch a short intro](https://www.youtube.com/watch?v=w6dSNCg9I5k) 📽️

<br>

![Llama](https://github.com/user-attachments/assets/df78f9ee-bb1d-4883-bf08-44371b0cd58a)

<br>

## Install

```sh
brew install --cask llama-app
```

Or download from [Releases](https://github.com/ggml-org/Llama-macOS/releases).

## How it works

When you start Llama, it runs a local server at `http://localhost:9931/v1`.

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
curl http://localhost:9931/v1/models
```

Send a message to a model:

```sh
curl http://localhost:9931/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ggml-org/gpt-oss-20b-GGUF:MXFP4",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

See complete API reference in the llama.cpp server [docs](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#api-endpoints).

## Custom model settings

The app configures each model for your Mac and writes that config to `models.ini`, which it regenerates on every launch. To change a setting, or add one the app doesn't set, edit `~/.config/llama/models.user.ini` instead -- the app only reads that file, and merges it into the config it generates.

Use the same section header the app uses (`org/repo:QUANT`), and list only the keys you want to change. Keys are `llama serve` options without the leading dashes.

```ini
[ggml-org/gemma-4-E4B-it-GGUF:Q8_0]
temp = 0.7
ctx-size = 32768
cache-type-k = q4_1
```

A section for a model the app didn't find is passed through as-is, which is how you point at weights or a draft model from another repo.

```ini
[unsloth/DeepSeek-V4-Flash-0731-GGUF:UD-Q2_K_XL]
model = /path/to/DeepSeek-V4-Flash-UD-Q2_K_XL.gguf
spec-type = draft-dspark
spec-draft-model = /path/to/draft.gguf
```

Anything you set here wins over the app's own value, including settings derived from how much memory your Mac has. If a key can't be applied, the app ignores the file and the menu says which option was at fault.

A commented template is written to this path on first launch.

## Network access

By default the server is reachable only from your Mac. "Allow network access" in Settings changes that, and what it offers depends on your setup.

`Tailscale` — binds the server to your Tailscale address. Your other devices reach it from anywhere, Tailscale authenticates and encrypts the connection, and the server stays invisible on whatever network you're on. This is the option to use on a laptop. Shown only when Tailscale is installed and signed in.

`This network` — binds all interfaces (`0.0.0.0`), so anything on your current network can reach it. The server has no password, so use it only on a network you trust, and never together with agent mode on a network you don't own.

## Experimental settings

**Bind to a specific address** — to pin the server to one address the app doesn't offer, set it by hand. The app leaves it alone, and falls back to localhost whenever the address isn't on any interface.

```sh
defaults write app.llama.Llama exposeToNetwork -string "192.168.1.50"
```

**Custom server arguments** — Extra CLI arguments appended to the `llama serve` command, for server flags the app doesn't expose (e.g. `--api-key`). They come after the app's own flags, so where the server honors the later occurrence they can override the app's settings. Takes effect on the next server start.

```sh
# append custom arguments to the server command
defaults write app.llama.Llama extraServerArgs -string "--api-key secret"

# remove (default)
defaults delete app.llama.Llama extraServerArgs
```
