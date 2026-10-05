## Issues

Use GitHub Issues for bug reports.

## Discussions

Use GitHub Discussions for feature requests and ideas.

As an early stage product, we prioritize easy wins (clear benefits, minimal costs, no ongoing maintenance burden) and high-leverage features (broad user impact, foundational improvements that enable future work).

We use Discussions to gather community feedback and gauge interest without cluttering the issue tracker. If a feature in Discussions is selected for development, we will open an Issue to track it.

## Pull Requests

Don't create PRs unless explicitly requested. Open an issue first.

Exception: Simple bug fixes (one file, obvious correctness, no architectural decisions) can be submitted directly.

## Publishing app updates

Sparkle reads the public feed at
`https://huggingface.co/buckets/ggml-org/install.sh/resolve/llama-macos/appcast.xml`.
After publishing the signed app archive and generating its appcast, upload the feed
with a maintainer's HF credentials that can write to `ggml-org/install.sh`:

```sh
bash scripts/publish-appcast.sh /path/to/generated/appcast.xml
```

Keep release notes embedded in the appcast's `description`. The app disables remote
release-note downloads and strips authorization from archive downloads because
Sparkle otherwise forwards the feed's optional HF token to those URLs. The existing
archive URLs and signing key do not change.

Before shipping the new feed URL, seed it with the current appcast and verify an
unauthenticated Sparkle update check against it. Keep publishing the old feed at
`https://releases.erusev.com/llama/appcast.xml`, or redirect it to the HF feed, so
older installations can still discover updates. Do not retire the old URL when
releasing the first version that uses HF.

## Engineering Principles

- **Keep it simple** — every addition must justify its weight
- **Don't over-engineer** — solve the problem at hand, not hypothetical future ones
- **Don't abstract prematurely** — don't abstract until patterns are proven stable
