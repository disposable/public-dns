#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/local-deploy.sh [options]

Run the public-dns publish pipeline locally in one script.

Options:
  --update-submodule              Refresh the crawler submodule to its latest remote commit
  --validation-parallelism N      Per-shard validator parallelism override (default: 5)
  --shards N                      Number of candidate shards to create (default: 10)
  --validate-jobs N               Number of shard validation jobs to run concurrently (default: shard count)
  --split-json-max-bytes N        Split JSON outputs into .part files up to N bytes (default: 100000000, set 0 to disable)
  --work-dir PATH                 Working directory for temporary stage artifacts (default: .local-deploy)
  --test-sample N                 Quick-test mode: skip discovery, sample N accepted servers from json/accepted.json
  --commit                        Commit generated changes at the end
  --push                          Push after committing
  --commit-message TEXT           Commit message to use when --commit is enabled
  --help                          Show this help

Environment overrides:
  VALIDATION_PARALLELISM
  SHARDS
  VALIDATE_JOBS
  SPLIT_JSON_MAX_BYTES
  LOCAL_DEPLOY_WORK_DIR
  LOCAL_DEPLOY_COMMIT
  LOCAL_DEPLOY_PUSH
  LOCAL_DEPLOY_COMMIT_MESSAGE
  LOCAL_DEPLOY_TEST_SAMPLE
EOF
}

log() {
  printf '[local-deploy] %s\n' "$*"
}

die() {
  printf '[local-deploy] ERROR: %s\n' "$*" >&2
  exit 1
}

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"
WORK_DIR="${LOCAL_DEPLOY_WORK_DIR:-$ROOT_DIR/.local-deploy}"
VALIDATION_PARALLELISM="${VALIDATION_PARALLELISM:-5}"
SHARDS="${SHARDS:-10}"
VALIDATE_JOBS="${VALIDATE_JOBS:-}"
SPLIT_JSON_MAX_BYTES="${SPLIT_JSON_MAX_BYTES:-100000000}"
COMMIT_CHANGES="${LOCAL_DEPLOY_COMMIT:-0}"
PUSH_CHANGES="${LOCAL_DEPLOY_PUSH:-0}"
COMMIT_MESSAGE="${LOCAL_DEPLOY_COMMIT_MESSAGE:-chore(data): refresh public DNS assets}"
UPDATE_SUBMODULE=0
TEST_SAMPLE="${LOCAL_DEPLOY_TEST_SAMPLE:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update-submodule)
      UPDATE_SUBMODULE=1
      shift
      ;;
    --validation-parallelism)
      VALIDATION_PARALLELISM="${2:?missing value for --validation-parallelism}"
      shift 2
      ;;
    --shards)
      SHARDS="${2:?missing value for --shards}"
      shift 2
      ;;
    --validate-jobs)
      VALIDATE_JOBS="${2:?missing value for --validate-jobs}"
      shift 2
      ;;
    --split-json-max-bytes)
      SPLIT_JSON_MAX_BYTES="${2:?missing value for --split-json-max-bytes}"
      shift 2
      ;;
    --work-dir)
      WORK_DIR="${2:?missing value for --work-dir}"
      shift 2
      ;;
    --commit)
      COMMIT_CHANGES=1
      shift
      ;;
    --push)
      PUSH_CHANGES=1
      shift
      ;;
    --commit-message)
      COMMIT_MESSAGE="${2:?missing value for --commit-message}"
      shift 2
      ;;
    --test-sample)
      TEST_SAMPLE="${2:?missing value for --test-sample}"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [[ -z "$VALIDATE_JOBS" ]]; then
  VALIDATE_JOBS="$SHARDS"
fi

[[ "$VALIDATION_PARALLELISM" =~ ^[0-9]+$ ]] || die "--validation-parallelism must be numeric"
[[ "$SHARDS" =~ ^[0-9]+$ ]] || die "--shards must be numeric"
[[ "$VALIDATE_JOBS" =~ ^[0-9]+$ ]] || die "--validate-jobs must be numeric"
[[ "$SPLIT_JSON_MAX_BYTES" =~ ^[0-9]+$ ]] || die "--split-json-max-bytes must be numeric"
[[ "$TEST_SAMPLE" =~ ^[0-9]+$ ]] || die "--test-sample must be numeric"
(( SHARDS > 0 )) || die "--shards must be greater than zero"
(( VALIDATE_JOBS > 0 )) || die "--validate-jobs must be greater than zero"
(( VALIDATION_PARALLELISM > 0 )) || die "--validation-parallelism must be greater than zero"

ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    return
  fi

  log "Installing uv because it is not available on this host"
  curl -LsSf https://astral.sh/uv/install.sh | sh

  export PATH="$HOME/.local/bin:$PATH"
  command -v uv >/dev/null 2>&1 || die "uv installation completed but uv is still not on PATH"
}

wait_for_slot() {
  while true; do
    local running
    running="$(jobs -rp | wc -l | tr -d ' ')"
    if (( running < VALIDATE_JOBS )); then
      break
    fi
    sleep 1
  done
}

run_validate_shard() {
  local shard="$1"
  local chunk_path="$WORK_DIR/discovery/chunks/chunk-${shard}.json"
  local output_path="$WORK_DIR/validated-shards/shard-${shard}.json"

  (
    cd "$ROOT_DIR/crawler"
    uv run resolver-inventory validate \
      --config configs/default.toml \
      --input "$chunk_path" \
      --probe-corpus "$WORK_DIR/probe-corpus/probe-corpus.json" \
      --validation-parallelism "$VALIDATION_PARALLELISM" \
      --output "$output_path"
  )
}

write_build_metadata() {
  local generated_at
  local repo_sha
  local run_id

  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  repo_sha="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  run_id="local-$(hostname)-$(date -u +%Y%m%dT%H%M%SZ)"

  mkdir -p "$ROOT_DIR/meta"
  cat >"$ROOT_DIR/meta/build.json" <<EOF
{
  "generated_at": "$generated_at",
  "workflow": "local-deploy",
  "run_id": "$run_id",
  "sha": "$repo_sha"
}
EOF
}

commit_outputs() {
  if [[ "$COMMIT_CHANGES" != "1" ]]; then
    log "Skipping git commit because --commit was not requested"
    return
  fi

  git -C "$ROOT_DIR" add README.md json txt probe-corpus meta crawler

  if git -C "$ROOT_DIR" diff --cached --quiet; then
    log "No changes to commit"
    return
  fi

  git -C "$ROOT_DIR" commit -m "$COMMIT_MESSAGE"

  if [[ "$PUSH_CHANGES" == "1" ]]; then
    git -C "$ROOT_DIR" push
  else
    log "Skipping git push because --push was not requested"
  fi
}

main() {
  ensure_uv

  cd "$ROOT_DIR"

  if [[ "$UPDATE_SUBMODULE" == "1" ]]; then
    log "Updating crawler submodule to its latest remote commit"
    git submodule update --init --remote --recursive crawler
  else
    git submodule update --init --recursive crawler
  fi

  log "Syncing crawler environment"
  (
    cd crawler
    export PATH="$HOME/.local/bin:$PATH"
    uv sync --group dev
  )

  log "Preparing local stage directories in $WORK_DIR"
  rm -rf "$WORK_DIR"
  mkdir -p \
    "$WORK_DIR/probe-corpus" \
    "$WORK_DIR/discovery/chunks" \
    "$WORK_DIR/meta" \
    "$WORK_DIR/validated-shards"

  if (( TEST_SAMPLE > 0 )); then
    log "Test-sample mode: skipping corpus generation and discovery, sampling $TEST_SAMPLE servers from json/accepted.json"
    [[ -f "$ROOT_DIR/json/accepted.json" ]] || die "json/accepted.json not found; run a full deploy first"
    [[ -f "$ROOT_DIR/probe-corpus/probe-corpus.json" ]] || die "probe-corpus/probe-corpus.json not found"

    # Stash inputs before we wipe the output directories.
    cp "$ROOT_DIR/json/accepted.json" "$WORK_DIR/accepted-snapshot.json"
    cp -R "$ROOT_DIR/probe-corpus/." "$WORK_DIR/probe-corpus/"
  fi

  mkdir -p "$ROOT_DIR/_build" "$ROOT_DIR/json" "$ROOT_DIR/txt" "$ROOT_DIR/probe-corpus"
  rm -rf "$ROOT_DIR/_build"/* "$ROOT_DIR/json"/* "$ROOT_DIR/txt"/* "$ROOT_DIR/probe-corpus"/*

  if (( TEST_SAMPLE > 0 )); then
    python3 - "$WORK_DIR/accepted-snapshot.json" "$WORK_DIR/discovery/candidates.json" "$TEST_SAMPLE" <<'PYEOF'
import json, random, sys
input_path, output_path, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(input_path) as f:
    data = json.load(f)
candidates = [entry["candidate"] for entry in data]
random.shuffle(candidates)
sample = candidates[:n]
with open(output_path, "w") as f:
    json.dump(sample, f, indent=2)
print(f"[local-deploy] Sampled {len(sample)} of {len(candidates)} accepted candidates")
PYEOF

    echo "[]" > "$WORK_DIR/discovery/filtered.json"
  else
    log "Generating probe corpus"
    (
      cd crawler
      uv run resolver-inventory generate-probe-corpus \
        --config configs/probe-corpus.toml \
        --output "$WORK_DIR/probe-corpus"
    )

    log "Validating probe corpus"
    (
      cd crawler
      uv run resolver-inventory validate-probe-corpus \
        --config configs/probe-corpus.toml \
        --input "$WORK_DIR/probe-corpus/probe-corpus.json" \
        --schema-version 2
    )

    log "Discovering candidates"
    (
      cd crawler
      uv run resolver-inventory discover \
        --config configs/default.toml \
        --output "$WORK_DIR/discovery/candidates.json" \
        --filtered-output "$WORK_DIR/discovery/filtered.json"
    )

    log "Applying historical DNS quarantine"
    (
      cd crawler
      uv run python scripts/apply_history_quarantine.py \
        --history-db "$ROOT_DIR/meta/history.duckdb" \
        --run-date "$(date -u +%F)" \
        --candidates-input "$WORK_DIR/discovery/candidates.json" \
        --filtered-input "$WORK_DIR/discovery/filtered.json" \
        --candidates-output "$WORK_DIR/discovery/candidates.json" \
        --filtered-output "$WORK_DIR/discovery/filtered.json"
    )
  fi

  log "Splitting candidates into $SHARDS shards"
  (
    cd crawler
    uv run resolver-inventory split-candidates \
      --input "$WORK_DIR/discovery/candidates.json" \
      --output-dir "$WORK_DIR/discovery/chunks" \
      --shards "$SHARDS"
  )

  git -C crawler rev-parse HEAD >"$WORK_DIR/meta/crawler-sha.txt"

  log "Validating shards with $VALIDATE_JOBS concurrent jobs and validation parallelism $VALIDATION_PARALLELISM"
  mapfile -t shard_files < <(find "$WORK_DIR/discovery/chunks" -maxdepth 1 -name 'chunk-*.json' | sort)
  for shard_file in "${shard_files[@]}"; do
    shard_id="$(basename "$shard_file" .json)"
    shard_id="${shard_id#chunk-}"
    wait_for_slot
    run_validate_shard "$shard_id" &
  done
  wait

  log "Materializing final outputs"
  (
    cd crawler
    materialize_cmd=(
      uv run resolver-inventory materialize-results
      --config configs/default.toml
      --inputs-glob "$WORK_DIR/validated-shards/*.json"
      --filtered-input "$WORK_DIR/discovery/filtered.json"
      --output "$ROOT_DIR/_build"
    )
    if (( SPLIT_JSON_MAX_BYTES > 0 )); then
      materialize_cmd+=(--split-json-max-bytes "$SPLIT_JSON_MAX_BYTES")
    fi
    "${materialize_cmd[@]}"
  )

  log "Copying probe corpus and published assets"
  cp -R "$WORK_DIR/probe-corpus/." "$ROOT_DIR/probe-corpus/"
  shopt -s nullglob
  for file in "$ROOT_DIR/_build"/*.json; do
    cp "$file" "$ROOT_DIR/json/"
  done
  for file in "$ROOT_DIR/_build"/*.txt "$ROOT_DIR/_build"/*.conf; do
    cp "$file" "$ROOT_DIR/txt/"
  done

  log "Writing local build metadata"
  write_build_metadata

  log "Updating history database"
  (
    cd crawler
    uv run python scripts/update_history.py \
      --history-db "$ROOT_DIR/meta/history.duckdb" \
      --accepted-input "$ROOT_DIR/_build/accepted.json" \
      --candidate-input "$ROOT_DIR/_build/candidate.json" \
      --rejected-input "$ROOT_DIR/_build/rejected.json" \
      --filtered-input "$ROOT_DIR/_build/filtered.json" \
      --meta-build "$ROOT_DIR/meta/build.json" \
      --crawler-sha-file "$WORK_DIR/meta/crawler-sha.txt"
  )

  log "Generating README statistics"
  (
    cd crawler
    uv run python scripts/generate_stats_report.py \
      --history-db "$ROOT_DIR/meta/history.duckdb" \
      --readme "$ROOT_DIR/README.md"
  )

  commit_outputs
  log "Local deploy run completed successfully"
}

main "$@"
