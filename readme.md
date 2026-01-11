# LlamaBarn

LlamaBarn is a tiny menu bar app that makes running local LLMs as easy as connecting to Wi-Fi.

<br>

![LlamaBarn](https://github.com/user-attachments/assets/a3cc6916-9f3a-41e2-b2ad-11e8e13c73d4)

<br>

## Installation

Install with `brew install --cask llamabarn` or download from [Releases ↗](https://github.com/ggml-org/LlamaBarn/releases)

## Why LlamaBarn

Running local LLMs from the command line is error-prone and time-consuming. You must handle model formats, quantization, context windows, device configurations, and prevent system freezes.

Other tools automate some tasks but often create new problems, such as bloated interfaces, proprietary abstractions, or cloud dependencies that complicate local workflows.

LlamaBarn stands out as a clean, platform-focused solution:

- **Platform, not a product** — Like Wi-Fi for your Mac, it lets you use local models in any app (chat UIs, editors, scripts) via a standard API — no vendor lock-in.
- **Native macOS app** — Tiny (`12 MB`) app built with Swift for optimal performance and minimal resource use.
- **Seamless llama.cpp integration** — Part of the GGML org and built alongside llama.cpp for optimal performance and reliability.
- **Built-in model catalog** — Auto-configured for optimal performance based on your Mac's specs and model recommendations.

## How it works

LlamaBarn runs as a menu bar app on your Mac.

- **Install a model from the built-in catalog** -- only models that can run on your Mac are shown
- **Select an installed model to run it** -- configures and starts a server at `http://localhost:2276`
- **Use the running model via the API or WebUI** -- both at `http://localhost:2276`

## Common use cases

Connect to any app that supports custom APIs, such as:

- **Chat UIs** like `Chatbox` or `Open WebUI`
- **CLI assistants** like [`OpenCode`](https://github.com/ggml-org/LlamaBarn/discussions/44) or `Codex`
- **Editors** like `VS Code` or `Zed` or [`Xcode`](https://github.com/ggml-org/LlamaBarn/discussions/43)
- **Editor extensions** like `Cline` or `Continue`
- **Custom scripts** using `curl` or libs like `AI SDK`

Or use the built-in WebUI at `http://localhost:2276` to chat with the running model directly.

## API Reference

LlamaBarn uses the llama.cpp server API. Example:

```sh
# say "Hello" to the running model
curl http://localhost:2276/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hello"}]}'
```

```sh
# info about the running model
GET http://localhost:2276/v1/models
```

```sh
# server and model configuration
GET http://localhost:2276/props
```

See complete reference in `llama-server` [docs ↗](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#api-endpoints)

## Advanced settings

LlamaBarn supports configuration through macOS `defaults`. These are advanced settings that are not yet available in the UI.

**Expose to network** — By default, the server is only accessible from your Mac (`localhost`). This option allows connections from other devices on your local network. Only enable this if you understand the security risks.

```sh
defaults write app.llamabarn.LlamaBarn exposeToNetwork -bool YES
```

## Roadmap

- [ ] Support for adding models outside the built-in catalog
- [ ] URL scheme and AppleScript commands for controlling LlamaBarn from other apps (e.g., start model X when app Y opens)
