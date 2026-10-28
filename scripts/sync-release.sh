#!/usr/bin/env sh
set -eu
TAG="${1:?tag required}"
REPO="justacalico/oasis-de"
RESP=$(curl -fsS -H "Authorization: token ${GH_TOKEN:-}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG")
LINKS=$(echo "$RESP" | python3 -c "
import json, sys
rel = json.load(sys.stdin)
links = []
for a in rel.get('assets', []):
    links.append({'name': a['name'], 'url': a['browser_download_url'], 'link_type': 'package', 'direct_asset_path': a['browser_download_url']})
print(json.dumps({'assets': {'links': links}}))
")
DESCRIPTION=$(echo "$RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('body','') or 'Oasis release')")
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
