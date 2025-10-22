# LlamaBarn 🦙 🌾

Run local LLMs on your Mac with a simple menu bar app. Launch any model with a single click, then chat with it via the built-in web UI or connect to it via the built-in REST API. LlamaBarn automatically configures models based on your Mac's hardware to ensure optimal performance and stability.

Get it from [Releases ↗](https://github.com/ggml-org/LlamaBarn/releases)

![LlamaBarn](https://github.com/user-attachments/assets/9ff133d8-6a65-43d5-9672-5eb58da0dd0e)

## Installation

### Homebrew

```shell
brew install --cask llamabarn
```

The formula is automatically updated with new LlamaBarn releases. Running the command above installs LlamaBarn in the `Applications` directory. 

### GitHub Releases

1. Download `LlamaBarn.dmg` from the [latest GitHub Release]() and open it.
2. Drag the LlamaBarn app over the `Applications` folder to install it.
3. Use <kbd>cmd + e</kbd> to eject the DMG.

Read the [Quick start](#quick-start) guide to start using LlamaBarn.

## Goals

<!-- what we hope to achieve -->

- **Make it easy for everyone to use local LLMs.** Using local LLMs should not require technical knowledge. You should be able to just select a model from a list and start using it. Technical customizations should be possible, but not required.
- **Make it easy for developers to add support for local LLMs to their apps.** Adding support for local LLMs should be just as easy as adding support for cloud-based LLMs. You shouldn't have to implement custom UIs for managing models, starting servers, etc.

## Features

<!-- what people like about it -->

- Tiny (`~12 MB`) macOS app built in Swift
- Curated model catalog
- Automatic model configuration based on your Mac's hardware
- Simple web UI that lets you chat with the running models
- Familiar REST API that lets you use the running models from other apps
- No side effects -- installed models live in `~/.llamabarn` and nothing is installed system-wide

## Quick start

To get started:

- Click on the menu bar icon to open the menu
- Select a model from the catalog to install it
- Select an installed model to run it — the app will figure out the optimal model settings for your Mac and start a local server at `http://localhost:2276`

Use the running models in two ways:

- In the browser via the built‑in web UI
- In other apps via the REST API

## API endpoints

LlamaBarn builds on the `llama.cpp` server (`llama-server`) and supports the same API endpoints:

```sh
# check server health
curl http://localhost:2276/v1/health
```

```sh
# chat with the running model
curl http://localhost:2276/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hi"}]}'
```

Find the complete reference in the [`llama-server` docs ↗](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#api-endpoints)

## Roadmap

- [ ] Embedding models
- [ ] Completion models
- [ ] Run multiple models at once
- [ ] Parallel requests
- [ ] Vision for models that support it
