## LlamaBarn 🦙 🌾

Run local LLMs on your Mac with a friendly menu bar app. Launch any model with a single click, then chat with it via the built-in web UI or use it via the REST API. LlamaBarn automatically configures models based on your Mac's hardware to ensure optimal performance and stability.

Download the latest version from [Releases ↗](https://github.com/ggml-org/LlamaBarn/releases).

<br>

![LlamaBarn](https://i.imgur.com/S2jzV6Y.png)

<br>

### Highlights

- Lightweight -- `~12 MB` or `~6 MB` zipped
- Curated model catalog
- Model configurations that adapt to your device's memory and GPU
- Basic web UI for interacting with running models
- Familiar REST API for developers

<br>

### How it works

- LlamaBarn is a thin wrapper around `llama.cpp`
- When you run a model, it launches `llama-server` on `localhost:2276`
- You can chat in the server's web UI or via the API

<br>

### API endpoints

LlamaBarn uses `llama-server` from `llama.cpp` and therefore supports the same API endpoints. Here are some examples to get you started.

```sh
# check server health
curl http://localhost:2276/v1/health
```

```sh
# list running models (limited to one at a time for now)
curl http://localhost:2276/v1/models
```

```sh
# chat with the running model
curl http://localhost:2276/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hi"}]}'
```

Find the full documentation for the API endpoints in the `llama.cpp` [docs](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#api-endpoints).

<br>

### Roadmap

- [ ] Support for embedding models
- [ ] Support for completion models
- [ ] Support for running multiple models at a time -- e.g., chat + embeddings
- [ ] Support for parallel requests
- [ ] Vision support for vision-capable models
- [ ] Advanced settings for power users -- without complicating things for everyone else

<br>

### License

Licensed under the MIT License. See `LICENSE`.
