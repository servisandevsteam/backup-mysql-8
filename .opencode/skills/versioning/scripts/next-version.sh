#!/bin/bash
set -euo pipefail

usage() {
  echo "uso: next-version.sh [--current X.Y.Z]" >&2
  exit 2
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../../../.." && pwd)
version_file="$repo_root/VERSION"

current=""
if [ "$#" -eq 2 ] && [ "$1" = "--current" ]; then
  current=$2
elif [ "$#" -ne 0 ]; then
  usage
fi

latest_tag=$(git -C "$repo_root" tag --list 'v*' --sort=-v:refname | sed -n '1s/^v//p')

if [ "$current" = "" ]; then
  if [ -f "$version_file" ]; then
    current=$(tr -d '[:space:]' < "$version_file")
  elif [ "$latest_tag" != "" ]; then
    current=$latest_tag
  else
    current="0.0.0"
  fi
fi

if ! [[ "$current" =~ ^([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{1,2})$ ]]; then
  echo "version invalida: '$current' (esperado X.Y.Z con componentes 0-99)" >&2
  exit 1
fi

major=$((10#${BASH_REMATCH[1]}))
minor=$((10#${BASH_REMATCH[2]}))
patch=$((10#${BASH_REMATCH[3]}))

if [ "$major" -gt 99 ] || [ "$minor" -gt 99 ] || [ "$patch" -gt 99 ]; then
  echo "version fuera de rango: '$current' (maximo 99.99.99)" >&2
  exit 1
fi

if [ "$latest_tag" != "" ] && [ "$latest_tag" != "$current" ]; then
  echo "VERSION ($current) no coincide con el ultimo tag (v$latest_tag)" >&2
  exit 1
fi

patch=$((patch + 1))
if [ "$patch" -gt 99 ]; then
  patch=0
  minor=$((minor + 1))
fi
if [ "$minor" -gt 99 ]; then
  minor=0
  major=$((major + 1))
fi
if [ "$major" -gt 99 ]; then
  echo "version agotada: 99.99.99 no tiene sucesor con la regla actual" >&2
  exit 1
fi

printf 'v%d.%d.%d\n' "$major" "$minor" "$patch"
