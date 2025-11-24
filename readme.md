# LlamaBarn 🦙 🌾

LlamaBarn is like Wi-Fi but for local LLMs. Pick a model from the menu bar, and it becomes available to all your apps through a standard REST API.
  
**Install** with `brew install --cask llamabarn` or download from [Releases ↗](https://github.com/ggml-org/LlamaBarn/releases)

<br>

![LlamaBarn](https://github.com/user-attachments/assets/9ff133d8-6a65-43d5-9672-5eb58da0dd0e)

<br>

## How it works

LlamaBarn runs as a tiny menu bar app on your Mac.

- Select a model to install it
- Select an installed model to run it -- LlamaBarn figures out the optimal settings for your Mac and starts a server at `http://localhost:2276`
- Use the running model in any app that supports custom LLM APIs -- or chat with it in your browser

Under the hood, LlamaBarn is a thin wrapper around `llama.cpp` and the `llama-server` that comes with it.

## API endpoints

LlamaBarn builds on `llama-server` and supports the same API endpoints:

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

Find the complete reference in the `llama-server` [docs ↗](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#api-endpoints)

## Roadmap

- [ ] Embedding models
- [ ] Completion models
- [ ] Run multiple models at once
- [x] Parallel requests
- [x] Vision for models that support it

## Questions

- **How does LlamaBarn compare to llama.cpp webUI?** — LlamaBarn doesn't replace the llama.cpp webUI, it builds on top of it — when you run a model in LlamaBarn it starts both the llama.cpp server and the llama.cpp webUI at `http://localhost:2276`.
- **How to use LlamaBarn with other apps?** — LlamaBarn exposes a standard REST API at `http://localhost:2276`. You can connect it to any app that supports custom LLM APIs. See the `API endpoints` section for example requests.
- **Why don't I see all models in the catalog?** — LlamaBarn shows only models that can run on your Mac based on its available memory. If a model you're looking for isn't in the catalog, it requires more memory than your system can provide.
- **Can I load models that aren't in the catalog?** — LlamaBarn uses a curated catalog where each model is tested and configured to work optimally across different Mac hardware setups. Loading arbitrary models isn't currently supported, but if there's a specific model you'd like to see added, feel free to open a feature request.
