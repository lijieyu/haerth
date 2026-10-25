#!/usr/bin/env bash
# Copy the ECS-served site files into ./public for Workers Static Assets.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ROOT}/public"

rm -rf "${DEST}"
mkdir -p "${DEST}/assets"

cp "${ROOT}/index.html" "${DEST}/index.html"
cp "${ROOT}/styles.css" "${DEST}/styles.css"
cp "${ROOT}/assets/gongan-beian.png" "${DEST}/assets/gongan-beian.png"

echo "Synced site files -> ${DEST}"
