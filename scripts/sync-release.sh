#!/usr/bin/env bash
set -euo pipefail
TAG="${1:?tag required}"
REPO="${GITHUB_REPO:-justacalico/oasis-de}"
AUTH=()
if [ -n "${GH_TOKEN:-}" ]; then
  AUTH=(-H "Authorization: token $GH_TOKEN")
fi
RESP=$(curl -fsS "${AUTH[@]}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG")
LINKS=$(echo "$RESP" | python3 -c "
import json, sys
rel = json.load(sys.stdin)
links = []
for a in rel.get('assets', []):
    links.append({'name': a['name'], 'url': a['browser_download_url'], 'link_type': 'package'})
print(json.dumps({'assets': {'links': links}}))
")
DESCRIPTION=$(echo "$RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('body','') or 'Oasis release')")
curl -fsS "${CI_API_V4_URL:-https://gitlab.com/api/v4}/projects/${CI_PROJECT_ID}/releases/$TAG" \
  -H "JOB-TOKEN: ${CI_JOB_TOKEN:-}" >/dev/null 2>&1 && \
  curl -fsS -X DELETE -H "JOB-TOKEN: ${CI_JOB_TOKEN:-}" \
  "${CI_API_V4_URL:-https://gitlab.com/api/v4}/projects/${CI_PROJECT_ID}/releases/$TAG" || true
curl -fsS -X POST -H "JOB-TOKEN: ${CI_JOB_TOKEN:-}" \
  -H "Content-Type: application/json" \
  "${CI_API_V4_URL:-https://gitlab.com/api/v4}/projects/${CI_PROJECT_ID}/releases" \
  -d "$(python3 -c "
import json, sys
links = json.loads(sys.argv[1])
print(json.dumps({
    'name': 'Oasis ' + sys.argv[2].lstrip('v'),
    'tag_name': sys.argv[2],
    'description': sys.argv[3],
    **links,
}))
" "$LINKS" "$TAG" "$DESCRIPTION")"
echo "release $TAG created"
