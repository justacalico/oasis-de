#!/usr/bin/env bash
set -euo pipefail
TAG="${1:?tag required}"
WORK=$(mktemp -d)
gh release download "$TAG" --repo justacalico/oasis-de --dir "$WORK" --pattern '*' 2>/dev/null || true
if compgen -G "$WORK/*" > /dev/null; then
  for f in "$WORK"/*; do
    curl -fsS --header "JOB-TOKEN: $CI_JOB_TOKEN" \
      --upload-file "$f" \
      "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/oasis/${TAG#v}/$(basename "$f")"
  done
fi
git tag -l "$TAG"
