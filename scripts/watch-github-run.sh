#!/usr/bin/env bash
set -euo pipefail
SHA="${CI_COMMIT_SHA:-$(git rev-parse HEAD)}"
for i in $(seq 1 120); do
  STATUS=$(gh api "repos/justacalico/oasis-de/commits/$SHA/check-runs" \
    --jq '.check_runs[] | select(.app.slug=="github-actions") | .conclusion // .status' 2>/dev/null | head -1 || true)
  case "$STATUS" in
    success) echo "github build passed"; exit 0 ;;
    failure|cancelled|timed_out|action_required) echo "github build failed: $STATUS"; exit 1 ;;
    "") echo "waiting for github run..." ;;
    *) echo "github build status: $STATUS" ;;
  esac
  sleep 15
done
echo "timed out waiting for github build"
exit 1
