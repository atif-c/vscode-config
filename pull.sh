#!/usr/bin/env bash
# pull.sh - repo -> live VS Code (reverse of push.sh).
# Shows every live path it would touch, asks [y/N], and copies repo
# state over live files only on "y". Any other answer aborts.
# Extensions: install-missing-only, never uninstall, report extras.
# extensions.ver.txt is audit-only and is never installed from.
# Never touched here: mcp.json, chatLanguageModels.json,
# globalStorage/, workspaceStorage/, History/, logs/, machineid.
# Out of scope: OS-level fonts.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"

# Windows username is asked at runtime (never hardcoded - avoids info disclosure).
# Override non-interactively with: WIN_USERNAME=someone ./pull.sh
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
installed=0

note_copy() { # $1 = label
  copied=$((copied + 1))
  echo "copied: $1"
}

# Strip CR/NUL/BOM bytes, drop blank lines, sort unique.
norm_list() { # $1 = src file, $2 = dest tmp file
  tr -d '\0\r' <"$1" | LC_ALL=C sed -e '1s/^[^A-Za-z0-9]*//' | grep -a -v '^[[:space:]]*$' | LC_ALL=C sort -u >"$2" || true
}

count_lines() { # $1 = file
  wc -l <"$1" | tr -d ' '
}

WIN_WANT="$(mktemp)"
WIN_INST="$(mktemp)"
WIN_MISS="$(mktemp)"
WIN_EXTRA="$(mktemp)"
WSL_WANT="$(mktemp)"
WSL_INST="$(mktemp)"
WSL_MISS="$(mktemp)"
WSL_EXTRA="$(mktemp)"
trap 'rm -f "$WIN_WANT" "$WIN_INST" "$WIN_MISS" "$WIN_EXTRA" "$WSL_WANT" "$WSL_INST" "$WSL_MISS" "$WSL_EXTRA"' EXIT
: >"$WIN_WANT"; : >"$WIN_INST"; : >"$WIN_MISS"; : >"$WIN_EXTRA"
: >"$WSL_WANT"; : >"$WSL_INST"; : >"$WSL_MISS"; : >"$WSL_EXTRA"

if [ -f "$REPO/extensions.txt" ]; then
  norm_list "$REPO/extensions.txt" "$WIN_WANT"
fi
if [ -f "$REPO/extensions-wsl.txt" ]; then
  norm_list "$REPO/extensions-wsl.txt" "$WSL_WANT"
fi

# --- installed lists: read-only probes, no live changes ---
# Windows side: prefer the Windows-side CLI; fall back to on-disk names.
win_cli=0
if command -v cmd.exe >/dev/null 2>&1; then
  if cmd.exe /c "code --list-extensions" 2>/dev/null | tr -d '\r' | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u >"$WIN_INST" && [ -s "$WIN_INST" ]; then
    win_cli=1
  fi
fi
if [ "$win_cli" -eq 0 ]; then
  : >"$WIN_INST"
  if [ -d "$WIN_EXT_DIR" ]; then
    for d in "$WIN_EXT_DIR"/*; do
      [ -e "$d" ] || continue
      base="$(basename "$d")"
      [ "$base" = "extensions.json" ] && continue
      [ -d "$d" ] || continue
      printf '%s\n' "$base" | sed -E 's/-[0-9][A-Za-z0-9._-]*$//'
    done | LC_ALL=C sort -u >"$WIN_INST" || true
  fi
fi

# WSL side: on-disk dir names mirror push.sh (strip version suffix, skip extensions.json).
if [ -d "$WSL_EXT_DIR" ]; then
  for d in "$WSL_EXT_DIR"/*; do
    [ -e "$d" ] || continue
    base="$(basename "$d")"
    [ "$base" = "extensions.json" ] && continue
    [ -d "$d" ] || continue
    printf '%s\n' "$base" | sed -E 's/-[0-9][A-Za-z0-9._-]*$//'
  done | LC_ALL=C sort -u >"$WSL_INST" || true
fi

comm -23 "$WIN_WANT" "$WIN_INST" >"$WIN_MISS" || true
comm -13 "$WIN_WANT" "$WIN_INST" >"$WIN_EXTRA" || true
comm -23 "$WSL_WANT" "$WSL_INST" >"$WSL_MISS" || true
comm -13 "$WSL_WANT" "$WSL_INST" >"$WSL_EXTRA" || true

# --- touch-list preview (no writes) ---
echo "pull.sh - repo -> live preview (no writes yet)"
echo "repo: $REPO"
echo "live user dir: $USER_DIR"
echo ""
echo "files that would be overwritten:"
for f in settings.json keybindings.json; do
  if [ -f "$REPO/$f" ]; then
    echo "  $USER_DIR/$f (from repo $f)"
  else
    echo "  $USER_DIR/$f (SKIP: not present in repo)"
  fi
done
if [ -d "$REPO/snippets" ]; then
  n_snip="$(find "$REPO/snippets" -type f 2>/dev/null | wc -l | tr -d ' ')"
  echo "  $USER_DIR/snippets/ (from repo snippets/, $n_snip files; dest created if needed)"
else
  echo "  $USER_DIR/snippets/ (SKIP: not present in repo)"
fi
if [ -d "$REPO/profiles" ]; then
  found_prof=0
  for src_profile in "$REPO/profiles"/*; do
    [ -e "$src_profile" ] || continue
    [ -d "$src_profile" ] || continue
    name="$(basename "$src_profile")"
    dest="$USER_DIR/profiles/$name"
    for pf in settings.json keybindings.json extensions.json; do
      if [ -f "$src_profile/$pf" ]; then
        echo "  $dest/$pf (from repo profiles/$name/$pf)"
        found_prof=1
      fi
    done
    if [ -d "$src_profile/snippets" ]; then
      n_psnip="$(find "$src_profile/snippets" -type f 2>/dev/null | wc -l | tr -d ' ')"
      echo "  $dest/snippets/ (from repo profiles/$name/snippets/, $n_psnip files)"
      found_prof=1
    fi
  done
  if [ "$found_prof" -eq 0 ]; then
    echo "  $USER_DIR/profiles/ (SKIP: no supported profile files in repo)"
  fi
else
  echo "  $USER_DIR/profiles/ (SKIP: not present in repo)"
fi
if [ -f "$REPO/Default.code-profile" ]; then
  echo "  $USER_DIR/Default.code-profile (from repo Default.code-profile)"
else
  echo "  $USER_DIR/Default.code-profile (SKIP: not present in repo)"
fi
if [ -s "$REPO/machine-settings.json" ]; then
  echo "  $MACHINE_SETTINGS (from repo machine-settings.json)"
else
  echo "  $MACHINE_SETTINGS (SKIP: missing or empty in repo)"
fi
echo ""
echo "extensions (install-missing-only, never uninstall; extras reported and kept):"
if [ -f "$REPO/extensions.txt" ]; then
  echo "  Windows: $(count_lines "$WIN_WANT") wanted (repo extensions.txt), $(count_lines "$WIN_INST") installed, $(count_lines "$WIN_MISS") to install, $(count_lines "$WIN_EXTRA") extras (kept)"
else
  echo "  Windows: SKIP (not present in repo: extensions.txt)"
fi
if [ -f "$REPO/extensions-wsl.txt" ]; then
  echo "  WSL: $(count_lines "$WSL_WANT") wanted (repo extensions-wsl.txt), $(count_lines "$WSL_INST") installed, $(count_lines "$WSL_MISS") to install, $(count_lines "$WSL_EXTRA") extras (kept)"
else
  echo "  WSL: SKIP (not present in repo: extensions-wsl.txt)"
fi
if [ -f "$REPO/extensions.ver.txt" ]; then
  echo "  extensions.ver.txt: $(count_lines "$REPO/extensions.ver.txt") entries (audit-only, never installed from)"
else
  echo "  extensions.ver.txt: not present (audit-only, never installed from)"
fi

echo ""
ans=""
read -r -p "Continue? [y/N] " ans || true
if [ "$ans" != "y" ]; then
  echo "aborted."
  exit 1
fi
echo ""

# --- apply: repo -> live ---
mkdir -p "$USER_DIR"

# settings.json / keybindings.json
for f in settings.json keybindings.json; do
  if [ -f "$REPO/$f" ]; then
    cp -f "$REPO/$f" "$USER_DIR/$f"
    note_copy "$USER_DIR/$f"
  else
    echo "skipped (not present in repo): $f"
  fi
done

# snippets/ passthrough
if [ -d "$REPO/snippets" ]; then
  mkdir -p "$USER_DIR/snippets"
  cp -r "$REPO/snippets/." "$USER_DIR/snippets/" 2>/dev/null || true
  note_copy "$USER_DIR/snippets/"
else
  echo "skipped (not present in repo): snippets/"
fi

# profiles/ filtered copy (only settings.json / keybindings.json / extensions.json / snippets/*)
if [ -d "$REPO/profiles" ]; then
  for src_profile in "$REPO/profiles"/*; do
    [ -e "$src_profile" ] || continue
    [ -d "$src_profile" ] || continue
    name="$(basename "$src_profile")"
    dest="$USER_DIR/profiles/$name"
    wrote=0
    for pf in settings.json keybindings.json extensions.json; do
      if [ -f "$src_profile/$pf" ]; then
        mkdir -p "$dest"
        cp -f "$src_profile/$pf" "$dest/$pf"
        wrote=1
      fi
    done
    if [ -d "$src_profile/snippets" ]; then
      mkdir -p "$dest/snippets"
      cp -r "$src_profile/snippets/." "$dest/snippets/" 2>/dev/null || true
      wrote=1
    fi
    if [ "$wrote" -eq 1 ]; then
      note_copy "$dest/"
    fi
  done
else
  echo "skipped (not present in repo): profiles/"
fi

# Default.code-profile passthrough (never generated)
if [ -f "$REPO/Default.code-profile" ]; then
  cp -f "$REPO/Default.code-profile" "$USER_DIR/Default.code-profile"
  note_copy "$USER_DIR/Default.code-profile"
else
  echo "skipped (not present in repo): Default.code-profile"
fi

# WSL machine settings (missing/empty in repo = skip)
if [ -s "$REPO/machine-settings.json" ]; then
  mkdir -p "$(dirname "$MACHINE_SETTINGS")"
  cp -f "$REPO/machine-settings.json" "$MACHINE_SETTINGS"
  note_copy "$MACHINE_SETTINGS"
else
  echo "skipped (missing or empty in repo): machine-settings.json"
fi

# Windows extensions: install missing only via Windows-side CLI, never uninstall.
if [ -f "$REPO/extensions.txt" ]; then
  if [ "$win_cli" -eq 1 ]; then
    while IFS= read -r ext; do
      [ -n "$ext" ] || continue
      if cmd.exe /c "code --install-extension $ext" >/dev/null 2>&1; then
        installed=$((installed + 1))
        echo "installed (Windows): $ext"
      else
        echo "FAILED (Windows): $ext"
      fi
    done <"$WIN_MISS"
  elif [ -s "$WIN_MISS" ]; then
    echo "skipped installs (Windows): Windows-side CLI not available; $(count_lines "$WIN_MISS") missing, left uninstalled"
  fi
  if [ -s "$WIN_EXTRA" ]; then
    echo "extras (Windows, kept, never uninstalled):"
    while IFS= read -r ext; do
      [ -n "$ext" ] || continue
      echo "  extra: $ext"
    done <"$WIN_EXTRA"
  fi
else
  echo "skipped (not present in repo): extensions.txt"
fi

# WSL extensions: install missing only, never uninstall.
if [ -f "$REPO/extensions-wsl.txt" ]; then
  if command -v code >/dev/null 2>&1; then
    while IFS= read -r ext; do
      [ -n "$ext" ] || continue
      if code --install-extension "$ext" >/dev/null 2>&1; then
        installed=$((installed + 1))
        echo "installed (WSL): $ext"
      else
        echo "FAILED (WSL): $ext"
      fi
    done <"$WSL_MISS"
  elif [ -s "$WSL_MISS" ]; then
    echo "skipped installs (WSL): CLI not available; $(count_lines "$WSL_MISS") missing, left uninstalled"
  fi
  if [ -s "$WSL_EXTRA" ]; then
    echo "extras (WSL, kept, never uninstalled):"
    while IFS= read -r ext; do
      [ -n "$ext" ] || continue
      echo "  extra: $ext"
    done <"$WSL_EXTRA"
  fi
else
  echo "skipped (not present in repo): extensions-wsl.txt"
fi

# --- summary ---
echo "---"
echo "pull done: $copied copied, $installed extensions installed. Repo: $REPO"
