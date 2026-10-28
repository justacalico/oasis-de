#!/usr/bin/env bash
set -euo pipefail
SHA="${CI_COMMIT_SHA:-$(git rev-parse HEAD)}"
REPO="justacalico/oasis-de"
for i in $(seq 1 120); do
  RESP=$(curl -fsS -H "Authorization: token ${GH_TOKEN:-}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/commits/$SHA/check-runs" 2>/dev/null || echo '{}')
  STATUS=$(echo "$RESP" | python3 -c "
import json, sys
try:
    runs = json.load(sys.stdin).get('check_runs', [])
except Exception:
    runs = []
runs = [r for r in runs if (r.get('app') or {}).get('slug') == 'github-actions']
runs.sort(key=lambda r: r.get('started_at') or '', reverse=True)
runs = runs[:2]
if not runs:
    print('')
elif any(r.get('status') != 'completed' for r in runs):
    print('running')
else:
    conclusions = {r.get('conclusion') for r in runs}
    print('success' if conclusions == {'success'} else 'failure')
")
  case "$STATUS" in
    success) echo "github build passed"; exit 0 ;;
    failure|cancelled|timed_out|action_required|neutral|skipped|stale)
      echo "github build failed: $STATUS"; exit 1 ;;
    "") echo "waiting for github run..." ;;
    *) echo "github build status: $STATUS" ;;
  esac
  sleep 15
done
echo "timed out waiting for github build"
exit 1
