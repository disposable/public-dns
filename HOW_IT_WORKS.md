# How it works

Pipeline internals for the published dataset. For the generated files see
the [README](README.md); for validation, scoring, and field semantics see
the [crawler README](https://github.com/disposable/public-dns-crawler#readme).

## Pipeline

Data is refreshed by GitHub Actions (`.github/workflows/publish-data.yml`),
daily on a schedule and manually via `workflow_dispatch`:

1. `discover-and-split`: checks out this repo and the `crawler` submodule,
   generates and validates the probe corpus, discovers candidates from the
   upstream sources, applies historical quarantine, and writes the validation
   shard inputs
2. `validate-shards`: runs a matrix job per shard where each runner validates
   one shard with configurable per-VM validation parallelism; candidates are
   dealt round-robin across shards so transports spread evenly
3. `merge-and-publish`: merges validated shards, materializes the output
   files, updates `meta/history.duckdb` (pushed to the `state` orphan branch),
   regenerates the README stats section, and commits changes; if the push is
   rejected because `main` moved, it rebases and retries

The `state` orphan branch carries run history (`history.duckdb`) and the
source fetch cache; validation shards read it so scoring sees prior runs
without locking the database.

Scoring components, reason codes, and the exported JSON field schema are
documented in the crawler's
[scoring system](https://github.com/disposable/public-dns-crawler#scoring-system)
and
[exported score fields](https://github.com/disposable/public-dns-crawler#exported-score-fields)
sections.

## Local reproduction

```bash
git submodule update --init --recursive

cd crawler
uv sync --group dev

uv run resolver-inventory generate-probe-corpus \
  --config configs/probe-corpus.toml \
  --output ../probe-corpus

uv run resolver-inventory validate-probe-corpus \
  --config configs/probe-corpus.toml \
  --input ../probe-corpus/probe-corpus.json

uv run resolver-inventory refresh \
  --config configs/default.toml \
  --probe-corpus ../probe-corpus/probe-corpus.json \
  --output ../_build
```

For server-side end-to-end runs without GitHub Actions stages, use
`scripts/local-deploy.sh`. It supports per-run overrides such as
`--validation-parallelism 12` and `--validate-jobs 10`.
Large JSON outputs can also be chunked with `--split-json-max-bytes`
(default in local deploy is `40000000` bytes).

Example:

```bash
bash scripts/local-deploy.sh \
  --validation-parallelism 8 \
  --validate-jobs 4
```
