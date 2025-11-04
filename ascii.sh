#!/usr/bin/env bash
set -euo pipefail

base_dir="$HOME/.config/fish/ascii"
shopt -s nullglob

# On récupère tous les fichiers .fish dans les deux sous-dossiers
files=("$base_dir"/spiderman/*.fish "$base_dir"/arch/*.fish)

shopt -u nullglob

if ((${#files[@]} > 0)); then
    printf '%s\0' "${files[@]}" | shuf -z -n1 | xargs -0 cat --
fi
