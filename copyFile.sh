#!/usr/bin/env bash

# Options :
#   -nf f1 f2 ...   exclure fichiers (basename OU chemin relatif)
#   -nr d1 d2 ...   exclure dossiers (basename OU chemin relatif)
#   -b              inclure les binaires en base64 (sinon: skipped)

EXCLUDED_FILES=()
EXCLUDED_DIRS=()
INCLUDE_BINARIES=0
TARGETS=()

# --- Parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -nf)
      shift
      while [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; do EXCLUDED_FILES+=("$1"); shift; done
      ;;
    -nr)
      shift
      while [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; do EXCLUDED_DIRS+=("$1"); shift; done
      ;;
    -b)
      INCLUDE_BINARIES=1; shift
      ;;
    *)
      TARGETS+=("$1"); shift
      ;;
  esac
done

# --- Helpers ---
trim_trailing_slash() { local x="$1"; x="${x%/}"; printf '%s' "$x"; }

# relpath depuis CWD, sans "./" devant
relpath_cwd() {
  local p="$1"
  # canonicalise "./"
  p="${p#./}"
  printf '%s' "$p"
}

# un fichier est-il dans un répertoire exclu ? (supporte ".git", ".git/", "path/to/dir")
is_under_excluded_dir() {
  local f_rel; f_rel="$(relpath_cwd "$1")"
  local ex exn
  for ex in "${EXCLUDED_DIRS[@]}"; do
    exn="$(trim_trailing_slash "$ex")"
    exn="${exn#./}"
    case "$f_rel" in
      "$exn"|"$exn"/*|*/"$exn"/*) return 0 ;;
    esac
  done
  return 1
}

# fichier explicitement exclu ? (si l'exclusion contient "/", on traite comme chemin relatif sinon basename)
is_excluded_file() {
  local f="$1"
  local f_base f_rel ex exn
  f_base="$(basename "$f")"
  f_rel="$(relpath_cwd "$f")"
  for ex in "${EXCLUDED_FILES[@]}"; do
    exn="$(trim_trailing_slash "$ex")"
    exn="${exn#./}"
    if [[ "$exn" == */* ]]; then
      # chemin (globs acceptés)
      [[ "$f_rel" == $exn ]] && return 0
    else
      # basename exact
      [[ "$f_base" == "$exn" ]] && return 0
    fi
  done
  return 1
}

# Détection binaire rapide : grep -Iq . => non-zero si binaire
is_binary() { grep -Iq . "$1"; [[ $? -ne 0 ]]; }

append_sep() { printf '\n---\n\n' >> "$TMPFILE"; }

process_file() {
  local file="$1"
  # Exclusions répertoires puis fichiers
  is_under_excluded_dir "$file" && return
  is_excluded_file "$file" && return

  printf '%s :\n\n' "$(relpath_cwd "$file")" >> "$TMPFILE"
  if is_binary "$file"; then
    if [[ $INCLUDE_BINARIES -eq 1 ]]; then
      printf '[[binary file, base64]]\n' >> "$TMPFILE"
      base64 "$file" >> "$TMPFILE"
      printf '\n' >> "$TMPFILE"
    else
      printf '[binary file skipped]\n' >> "$TMPFILE"
    fi
  else
    cat "$file" >> "$TMPFILE"
    printf '\n' >> "$TMPFILE"
  fi
  append_sep
}

process_dir() {
  local dir="$1"
  # On parcourt tout puis on filtre par is_under_excluded_dir
  while IFS= read -r -d '' f; do
    process_file "$f"
  done < <(find "$dir" -type f -print0)
}

# --- Accumulation dans un fichier temporaire (évite les NUL warnings) ---
TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

# --- Traitement principal ---
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  process_dir "."
else
  for item in "${TARGETS[@]}"; do
    if [[ -f "$item" ]]; then
      process_file "$item"
    elif [[ -d "$item" ]]; then
      process_dir "$item"
    else
      printf 'Warning: %s not found, skipped.\n' "$item" >&2
    fi
  done
fi

# --- Clipboard (X11 ou Wayland) ---
if command -v xclip >/dev/null 2>&1; then
  cat "$TMPFILE" | xclip -selection clipboard
elif command -v wl-copy >/dev/null 2>&1; then
  cat "$TMPFILE" | wl-copy
else
  echo "No clipboard tool found (install xclip or wl-clipboard)." >&2
  exit 1
fi

echo "✅ Content copied to clipboard."

