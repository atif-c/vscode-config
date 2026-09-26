#!/usr/bin/env bash
# push.sh — live VS Code -> repo (source of truth: live).
# No prompt. Overwrites repo files with live state. Never touches live files.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"

# Windows username is asked at runtime (never hardcoded - avoids info disclosure).
# Override non-interactively with: WIN_USERNAME=someone ./push.sh
WIN_USER="${WIN_USERNAME:-}"
if [ -z "$WIN_USER" ]; then
  read -r -p "Windows username: " WIN_USER || true
fi
if [ -z "${WIN_USER:-}" ]; then
  echo "error: Windows username is required." >&2
  exit 1
fi
case "$WIN_USER" in
  *[/\\]*|*..*)
    echo "error: invalid Windows username." >&2
    exit 1
    ;;
esac
USER_DIR="/mnt/c/Users/$WIN_USER/AppData/Roaming/Code/User"
WIN_EXT_DIR="/mnt/c/Users/$WIN_USER/.vscode/extensions"
WSL_EXT_DIR="$HOME/.vscode-server/extensions"
MACHINE_SETTINGS="$HOME/.vscode-server/data/Machine/settings.json"

copied=0
skipped=0

note_copy() { # $1 = label
  copied=$((copied + 1))
  echo "copied: $1"
}
note_skip() { # $1 = label
  skipped=$((skipped + 1))
  echo "skipped (not present live): $1"
}

# --- settings.json / keybindings.json ---
for f in settings.json keybindings.json; do
  if [ -f "$USER_DIR/$f" ]; then
    cp -f "$USER_DIR/$f" "$REPO/$f"
    note_copy "$f"
  else
    note_skip "$f"
  fi
done

# --- Windows extensions (client) ---
# Must use the Windows-side CLI: the WSL-shim `code --list-extensions`
# undercounts (12 vs 18) and drops e.g. vscode-icons, errorlens.
WIN_EXT_TMP="$(mktemp)"
WIN_VER_TMP="$(mktemp)"
trap 'rm -f "$WIN_EXT_TMP" "$WIN_VER_TMP"' EXIT
win_cli_ok=0
if command -v cmd.exe >/dev/null 2>&1; then
  if cmd.exe /c "code --list-extensions" 2>/dev/null | tr -d '\r' | grep -v '^[[:space:]]*$' | LC_ALL=C sort >"$WIN_EXT_TMP" && [ -s "$WIN_EXT_TMP" ]; then
    win_cli_ok=1
  fi
  if cmd.exe /c "code --list-extensions --show-versions" 2>/dev/null | tr -d '\r' | grep -v '^[[:space:]]*$' | LC_ALL=C sort >"$WIN_VER_TMP" && [ -s "$WIN_VER_TMP" ]; then
    :
  else
    rm -f "$WIN_VER_TMP"; touch "$WIN_VER_TMP"
  fi
fi
if [ "$win_cli_ok" -eq 0 ]; then
  # Fallback: parse on-disk dir names (strip trailing -<version>, skip extensions.json).
  : >"$WIN_EXT_TMP"
  if [ -d "$WIN_EXT_DIR" ]; then
    for d in "$WIN_EXT_DIR"/*; do
      [ -e "$d" ] || continue
      base="$(basename "$d")"
      [ "$base" = "extensions.json" ] && continue
      [ -d "$d" ] || continue
      printf '%s\n' "$base" | sed -E 's/-[0-9][A-Za-z0-9._-]*$//'
    done | LC_ALL=C sort >"$WIN_EXT_TMP"
  fi
  # Best-effort versions file from extensions.json is not reliable; leave audit file from CLI only.
  if [ ! -s "$WIN_VER_TMP" ]; then
    : >"$WIN_VER_TMP"
    if [ -s "$WIN_EXT_TMP" ]; then
      cp -f "$WIN_EXT_TMP" "$WIN_VER_TMP"
    fi
  fi
fi
# Sorted UTF-8 LF (no CR, no BOM).
tr -d '\r' <"$WIN_EXT_TMP" | LC_ALL=C sort >"$REPO/extensions.txt"
tr -d '\r' <"$WIN_VER_TMP" | LC_ALL=C sort >"$REPO/extensions.ver.txt"
trap - EXIT
rm -f "$WIN_EXT_TMP" "$WIN_VER_TMP"
echo "extensions.txt: $(wc -l <"$REPO/extensions.txt" | tr -d ' ') entries"
echo "extensions.ver.txt: $(wc -l <"$REPO/extensions.ver.txt" | tr -d ' ') entries (audit only)"

# --- snippets/ passthrough ---
rm -rf "$REPO/snippets"
if [ -d "$USER_DIR/snippets" ]; then
  mkdir -p "$REPO/snippets"
  # Copy contents (dir currently empty); -r handles any nested files.
  cp -r "$USER_DIR/snippets/." "$REPO/snippets/" 2>/dev/null || true
  note_copy "snippets/ ($(find "$REPO/snippets" -type f 2>/dev/null | wc -l | tr -d ' ') files)"
else
  note_skip "snippets/"
fi

# --- profiles/ filtered copy ---
# Per profile: only settings.json / keybindings.json / snippets/* / extensions.json.
# EXCLUDE: globalStorage/, *.vscdb, *.backup (and everything else).
rm -rf "$REPO/profiles"
if [ -d "$USER_DIR/profiles" ]; then
  for src_profile in "$USER_DIR/profiles"/*; do
    [ -e "$src_profile" ] || continue
    [ -d "$src_profile" ] || continue
    name="$(basename "$src_profile")"
    dest="$REPO/profiles/$name"
    for f in settings.json keybindings.json extensions.json; do
      if [ -f "$src_profile/$f" ]; then
        mkdir -p "$dest"
        cp -f "$src_profile/$f" "$dest/$f"
      fi
    done
    if [ -d "$src_profile/snippets" ]; then
      mkdir -p "$dest/snippets"
      cp -r "$src_profile/snippets/." "$dest/snippets/" 2>/dev/null || true
    fi
    if [ -d "$dest" ]; then
      # Drop anything excluded that may have slipped in (belts and braces).
      find "$dest" \( -name '*.vscdb' -o -name '*.backup' \) -delete 2>/dev/null || true
      rm -rf "$dest/globalStorage" 2>/dev/null || true
      note_copy "profiles/$name/"
    fi
  done
  [ -d "$REPO/profiles" ] || mkdir -p "$REPO/profiles"
  echo "profiles/: $(find "$REPO/profiles" -type f 2>/dev/null | wc -l | tr -d ' ') files"
else
  mkdir -p "$REPO/profiles"
  note_skip "profiles/"
fi

# --- Default.code-profile passthrough (manual export; never generate) ---
if [ -f "$USER_DIR/Default.code-profile" ]; then
  cp -f "$USER_DIR/Default.code-profile" "$REPO/Default.code-profile"
  note_copy "Default.code-profile"
else
  note_skip "Default.code-profile"
fi

# --- WSL machine settings (missing = empty file, don't error) ---
if [ -f "$MACHINE_SETTINGS" ]; then
  cp -f "$MACHINE_SETTINGS" "$REPO/machine-settings.json"
  note_copy "machine-settings.json"
else
  : >"$REPO/machine-settings.json"
  note_skip "machine-settings.json (wrote empty file)"
fi

# --- WSL extensions (strip version suffix, skip extensions.json) ---
: >"$REPO/extensions-wsl.txt"
if [ -d "$WSL_EXT_DIR" ]; then
  for d in "$WSL_EXT_DIR"/*; do
    [ -e "$d" ] || continue
    base="$(basename "$d")"
    [ "$base" = "extensions.json" ] && continue
    [ -d "$d" ] || continue
    printf '%s\n' "$base" | sed -E 's/-[0-9][A-Za-z0-9._-]*$//'
  done | LC_ALL=C sort | tr -d '\r' >"$REPO/extensions-wsl.txt"
fi
echo "extensions-wsl.txt: $(wc -l <"$REPO/extensions-wsl.txt" | tr -d ' ') entries"

# --- summary ---
echo "---"
echo "push done: $copied copied, $skipped skipped. Repo: $REPO"
