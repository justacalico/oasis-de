#!/usr/bin/env bash
set -euo pipefail
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
    links.append({'name': a['name'], 'url': a['browser_download_url'], 'link_type': 'package'})
if not links:
    tag = rel.get('tag_name', '')
    for n in ('oasis-linux-x64.tar.gz', 'oasis-linux-arm64.tar.gz'):
        links.append({'name': n, 'url': f'https://github.com/$REPO/releases/download/{tag}/{n}', 'link_type': 'package'})
print(json.dumps(links))
")
DESCRIPTION=$(git tag -l --format='%(contents)' "$TAG" | head -200)
release-cli create \
  --name "Oasis ${TAG#v}" \
  --tag-name "$TAG" \
  --description "$DESCRIPTION" \
  --assets-links "$LINKS"
echo "release $TAG created"
