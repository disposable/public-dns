# How it works

Pipeline and scoring internals for the public resolver dataset. For the
generated files themselves, see the [README](README.md).

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
   regenerates the README stats section, and commits changes

The `state` orphan branch carries the run history (`history.duckdb`) and the
source fetch cache; validation shards read it so scoring sees prior runs
without locking the database.

## Scoring system

Each resolver receives a composite `score` (0-100) based on four weighted
components:

| Component | Weight | Description |
|-----------|--------|-------------|
| Correctness | 0-50 | DNS/TLS errors, answer mismatches, NXDOMAIN spoofing |
| Availability | 0-20 | Probe success rate (100% = 20 pts) |
| Performance | 0-20 | Latency penalties for p50, p95, and jitter |
| History | 0-10 | Stability rewards, flapping/failure penalties |

**Score caps** may be applied:

- 0-2 runs observed: max 90
- 3-6 runs: max 95
- 7-13 runs: max 98
- 14+ runs: no cap

Severe correctness issues (NXDOMAIN spoofing, TLS mismatch, answer mismatch)
cap scores at <=59.

**Confidence score** (0-100) reflects measurement certainty separately from
quality. It considers probe count, latency samples, historical observations,
and source reliability metadata.

## Exported JSON fields

Each resolver entry includes:

```json
{
  "status": "accepted",
  "score": 87,
  "score_breakdown": {
    "correctness": 50,
    "availability": 18,
    "performance": 12,
    "history": 7
  },
  "confidence_score": 65,
  "score_caps_applied": ["insufficient_history"],
  "derived_metrics": {
    "p50_latency_ms": 45.2,
    "p95_latency_ms": 120.5,
    "jitter_ms": 75.3,
    "latency_sample_count": 10,
    "runs_seen_30d": 5,
    "runs_seen_7d": 3,
    "flaps_30d": 0,
    "consecutive_success_days": 5,
    "consecutive_fail_days": 0
  },
  "capabilities": {
    "dnssec_validating": true,
    "ecs_support": false,
    "filters_detected": null
  },
  "reasons": ["latency_high"]
}
```

`capabilities` is measured per resolver (DNSSEC validation, EDNS Client
Subnet support, domain filtering detection) and is informational only - it
never affects the score. Values are `true`, `false`, or `null` when a check
was inconclusive.

Large JSON files may be split into `*.part-XXXX.json` files to stay below
repository limits. When that happens, the part files together replace the
unsplit file.

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
