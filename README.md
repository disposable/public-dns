# Public DNS and DoH resolver data

Published public DNS and DoH resolver datasets, generated automatically from the [`crawler`](https://github.com/disposable/public-dns-crawler) submodule.

This repository is the **data/output repo**.
The crawler code lives in the submodule; this repo stores the generated assets.

## Contents

- `json/` — machine-readable resolver data
- `txt/` — plain-text resolver lists
- `csv/` — CSV exports
- `probe-corpus/` — generated probe definitions used for validation
- `meta/` — build metadata
- `crawler/` — git submodule with the generator/crawler code

## Updates

Data is refreshed by GitHub Actions:

- daily on a schedule
- manually via the Actions tab

The workflow:

1. checks out this repo and the `crawler` submodule
2. generates and validates the probe corpus
3. refreshes resolver data using that corpus
4. commits changes if outputs changed

## Usage

Consume the generated files directly from this repository.

For reproducible use, pin to a specific commit instead of following the latest repository state.

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
