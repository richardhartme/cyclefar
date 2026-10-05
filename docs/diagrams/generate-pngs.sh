#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if ! command -v plantuml >/dev/null 2>&1; then
  echo "Error: install PlantUML and make the plantuml command available on PATH." >&2
  exit 1
fi

shopt -s nullglob
sources=(./*.puml)
if (( ${#sources[@]} == 0 )); then
  echo "Error: no .puml files found in $PWD." >&2
  exit 1
fi

mkdir -p png
export PLANTUML_LIMIT_SIZE="${PLANTUML_LIMIT_SIZE:-16384}"
plantuml --check-before-run --no-error-image --disable-metadata --png --output-dir png "${sources[@]}"

echo "Generated ${#sources[@]} PNG diagrams in $PWD/png."
