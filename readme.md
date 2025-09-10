# LlamaBarn

Run local LLMs on your Mac with a friendly menu bar app and an OpenAI-compatible API.

Get the latest build from [Releases ↗](https://github.com/ggml-org/LlamaBarn/releases)

![LlamaBarn](https://i.imgur.com/S2jzV6Y.png)

## Highlights

- Lightweight app -- `~12 MB` or `~6 MB` zipped
- Curated model catalog with sensible defaults
- Optimal model configs based on your Mac's memory and GPU
- Guardrails against running models that would freeze your Mac
- Built-in chat via llama.cpp's web UI
- Compatible API

## API Endpoints

Check server health
```sh
curl http://localhost:2276/v1/health
```

List running models (right now, you can only run one at a time)
```sh
curl http://localhost:2276/v1/models
```

Chat with the running model
```sh
curl http://localhost:2276/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hi"}]}'
```

Learn more at in the `llama-server` [docs](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#api-endpoints).

## How it works

- LlamaBarn is a thin wrapper around `llama.cpp`
- When you run a model, it launches `llama-server` on `localhost:2276`
- You can chat in the server's web UI or via the API

## Roadmap

- [ ] Run multiple models at once (e.g., chat + embeddings)
- [ ] Embedding models support
- [ ] Completion models support
- [ ] Vision for models that support it
- [ ] Expose advanced settings like context length, temperature, etc.

## License and acknowledgements

Licensed under the MIT License. See `LICENSE`.

Built on top of the `llama.cpp` and `ggml` ecosystem.
