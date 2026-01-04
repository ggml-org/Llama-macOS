# LlamaBarn

LlamaBarn is a tiny menu bar app that makes running local LLMs as easy as connecting to Wi-Fi.

<br>

![LlamaBarn](https://github.com/user-attachments/assets/ec4237e4-3a7b-41b7-8506-445838f0519f)

<br>

## Installation

Install with `brew install --cask llamabarn` or download from [Releases ↗](https://github.com/ggml-org/LlamaBarn/releases)

## Why LlamaBarn

Running local LLMs from the command line is error-prone and time-consuming. You must handle model formats, quantization, context windows, device configurations, and prevent system freezes.

Other tools automate some tasks but often create new problems, such as bloated interfaces, proprietary abstractions, or cloud dependencies that complicate local workflows.

LlamaBarn stands out as a clean, platform-focused solution:

- **Platform, not a product** — Like Wi-Fi for your Mac, it lets you use local models in any app (chat UIs, editors, scripts) via a standard API — no vendor lock-in.
- **Native macOS App** — Tiny (`12 MB`) app built with Swift for optimal performance and minimal resource use.
- **Seamless llama.cpp integration** — Part of the GGML org and built alongside llama.cpp for optimal performance and reliability.
- **Built-in model catalog** — Auto-configured for optimal performance based on your Mac's specs and model recommendations.

## How it works

LlamaBarn runs as a menu bar app on your Mac.

- **Install a model from the built-in catalog** -- only models that can run on your Mac are shown
- **Select an installed model to run it** -- configures and starts a server at `http://localhost:2276`
- **Use the running model via the API or web UI** -- both at `http://localhost:2276`

## Common use cases

Connect to any app that supports custom APIs, such as:

- **Chat UIs** like `Chatbox` or `Open WebUI`
- **CLI assistants** like `OpenCode` or `Codex`
- **Editors** like `VS Code` or `Zed`
- **Editor extensions** like `Cline` or `Continue`
- **Custom scripts** using `curl` or libs like `AI SDK`

Or use the built-in web UI at `http://localhost:2276` to chat with the running model directly.

## API Reference

LlamaBarn uses the llama.cpp server API. Example:

```sh
# say "Hello" to the running model
curl http://localhost:2276/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hello"}]}'
```

See complete reference in `llama-server` [docs ↗](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#api-endpoints)

## Roadmap

- [ ] Option to expose to local network
- [ ] Support for adding models outside the built-in catalog
