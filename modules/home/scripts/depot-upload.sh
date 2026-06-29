#!/usr/bin/env bash
#
# depot-upload: capture a screenshot (or take a file / the clipboard) and upload
# it to Hivecom's depot, then copy the returned URL to the clipboard.
#
# Auth: a Depot API key (depot_...), resolved from $DEPOT_API_KEY or a file at
# $DEPOT_KEY_FILE (one line). Mint one at https://hivecom.net/sharing.
#
# Subcommands:
#   file <path>   upload an existing file
#   shot-full     full-screen screenshot -> upload
#   shot-region   interactive region/window screenshot -> upload
#   clipboard     upload the image currently on the clipboard
#
# Cross-platform: macOS and Linux/Wayland.
#   macOS  - tools are referenced by absolute path so this works under
#            launchd/skhd, which runs with a minimal PATH.
#   Linux  - tools are called by name (curl, grim, slurp, wl-copy/wl-paste,
#            notify-send). The Nix wrapper puts them on PATH so the Plasma
#            global shortcut, which also runs with a minimal PATH, finds them.

set -euo pipefail

DEPOT_URL="${DEPOT_URL:-https://depot.hivecom.net}"
MAX_BYTES=$((100 * 1024 * 1024)) # depot rejects files over 100 MB

OS="$(uname)"

if [ "$OS" = "Darwin" ]; then
  CURL=/usr/bin/curl
  SCREENCAPTURE=/usr/sbin/screencapture
  PBCOPY=/usr/bin/pbcopy
  PBPASTE=/usr/bin/pbpaste
  OSASCRIPT=/usr/bin/osascript
  STAT=/usr/bin/stat
else
  CURL=curl
  STAT=stat
fi

notify() { # title, message
  if [ "$OS" = "Darwin" ]; then
    [ -x "$OSASCRIPT" ] || return 0
    "$OSASCRIPT" -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
  else
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send "$1" "$2" >/dev/null 2>&1 || true
  fi
}

# Copy stdin to the clipboard.
clip_copy() {
  if [ "$OS" = "Darwin" ]; then
    "$PBCOPY"
  else
    wl-copy
  fi
}

fail() {
  notify "Depot upload failed" "$1"
  echo "depot-upload: $1" >&2
  exit 1
}

read_key() {
  if [ -n "${DEPOT_API_KEY:-}" ]; then
    printf '%s' "$DEPOT_API_KEY"
  elif [ -n "${DEPOT_KEY_FILE:-}" ] && [ -r "$DEPOT_KEY_FILE" ]; then
    tr -d '\n' <"$DEPOT_KEY_FILE"
  else
    fail "no depot key (set DEPOT_API_KEY or DEPOT_KEY_FILE)"
  fi
}

filesize() {
  if [ "$OS" = "Darwin" ]; then
    "$STAT" -f%z "$1"
  else
    "$STAT" -c%s "$1"
  fi
}

# Make a temp file with a clean basename (it shows up in the depot URL).
# Returns the path; the caller removes the parent dir with: rm -rf "${out%/*}"
tmp_named() { # filename
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/depot.XXXXXX")"
  printf '%s/%s' "$dir" "$1"
}

upload() { # path
  local f="$1" key resp url errfile size
  [ -f "$f" ] || fail "file not found: $f"

  size="$(filesize "$f")"
  if [ "$size" -gt "$MAX_BYTES" ]; then
    fail "file is $((size / 1024 / 1024)) MB, over the 100 MB depot limit"
  fi

  key="$(read_key)"
  errfile="$(mktemp "${TMPDIR:-/tmp}/depot-err.XXXXXX")"
  if ! resp="$("$CURL" -fsS \
    -H "Authorization: Bearer $key" \
    -F "file=@$f" \
    "$DEPOT_URL/upload" 2>"$errfile")"; then
    local detail
    detail="$(cat "$errfile" 2>/dev/null || true)"
    rm -f "$errfile"
    fail "request failed: ${detail:-unknown error}"
  fi
  rm -f "$errfile"

  # Pull "url" out of the JSON response without depending on jq.
  url="$(printf '%s' "$resp" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  [ -n "$url" ] || fail "no url in response: $resp"

  printf '%s' "$url" | clip_copy
  notify "Depot upload" "Copied: $url"
  echo "$url"
}

cmd_shot_full() {
  local out
  out="$(tmp_named screenshot.png)"
  if [ "$OS" = "Darwin" ]; then
    "$SCREENCAPTURE" -x "$out" # -x: silent, no shutter sound
  else
    grim "$out"
  fi
  upload "$out"
  rm -rf "${out%/*}"
}

cmd_shot_region() {
  local out geom
  out="$(tmp_named screenshot.png)"
  if [ "$OS" = "Darwin" ]; then
    "$SCREENCAPTURE" -i "$out" # interactive region/window select
  else
    # slurp exits non-zero if the user presses Esc -> quiet cancel.
    if ! geom="$(slurp)"; then
      rm -rf "${out%/*}"
      exit 0
    fi
    grim -g "$geom" "$out"
  fi
  # No file written (Esc on macOS, empty grab on Linux) -> quiet cancel.
  if [ ! -s "$out" ]; then
    rm -rf "${out%/*}"
    exit 0
  fi
  upload "$out"
  rm -rf "${out%/*}"
}

cmd_clipboard_macos() {
  local out path

  # A copied file in Finder (Cmd-C) -> upload the real file, keeping its name.
  # «class furl» is a file reference on the pasteboard; errors out if absent.
  # If several files are copied this grabs the first one.
  if path="$("$OSASCRIPT" -e 'POSIX path of (the clipboard as «class furl»)' 2>/dev/null)" \
    && [ -n "$path" ] && [ -f "$path" ]; then
    upload "$path"
    return
  fi

  # Otherwise an image. «class PNGf» is the AppleScript four-char code for PNG;
  # this errors out (and writes nothing) if the clipboard holds no image.
  out="$(tmp_named clipboard.png)"
  if "$OSASCRIPT" - "$out" >/dev/null 2>&1 <<'OSA' && [ -s "$out" ]; then
on run argv
  set p to item 1 of argv
  set d to (the clipboard as «class PNGf»)
  set f to open for access (POSIX file p) with write permission
  set eof of f to 0
  write d to f
  close access f
end run
OSA
    upload "$out"
    rm -rf "${out%/*}"
    return
  fi
  rm -rf "${out%/*}"

  # No image, fall back to clipboard text uploaded as a .txt file.
  out="$(tmp_named clipboard.txt)"
  "$PBPASTE" >"$out" 2>/dev/null || true
  if [ -s "$out" ]; then
    upload "$out"
    rm -rf "${out%/*}"
  else
    rm -rf "${out%/*}"
    fail "clipboard has no file, image, or text"
  fi
}

cmd_clipboard_linux() {
  local out types

  types="$(wl-paste --list-types 2>/dev/null || true)"

  # A file copied from a file manager arrives as text/uri-list. Upload the first
  # local file, keeping its name (mirrors the macOS furl path above).
  if printf '%s\n' "$types" | grep -qi '^text/uri-list'; then
    local uri path
    uri="$(wl-paste --type text/uri-list 2>/dev/null | head -n1 | tr -d '\r')"
    case "$uri" in
    file://*)
      # Percent-decode the URI body (file:///foo%20bar -> /foo bar).
      path="$(printf '%b' "$(printf '%s' "${uri#file://}" | sed 's/%/\\x/g')")"
      if [ -f "$path" ]; then
        upload "$path"
        return
      fi
      ;;
    esac
  fi

  # An image on the clipboard -> upload as PNG.
  if printf '%s\n' "$types" | grep -qi '^image/'; then
    out="$(tmp_named clipboard.png)"
    if wl-paste --type image/png >"$out" 2>/dev/null && [ -s "$out" ]; then
      upload "$out"
      rm -rf "${out%/*}"
      return
    fi
    rm -rf "${out%/*}"
  fi

  # Fall back to clipboard text uploaded as a .txt file.
  out="$(tmp_named clipboard.txt)"
  if wl-paste --no-newline >"$out" 2>/dev/null && [ -s "$out" ]; then
    upload "$out"
    rm -rf "${out%/*}"
  else
    rm -rf "${out%/*}"
    fail "clipboard has no file, image, or text"
  fi
}

cmd_clipboard() {
  if [ "$OS" = "Darwin" ]; then
    cmd_clipboard_macos
  else
    cmd_clipboard_linux
  fi
}

case "${1:-}" in
file)
  shift
  upload "${1:?usage: depot-upload file <path>}"
  ;;
shot-full | full) cmd_shot_full ;;
shot-region | region) cmd_shot_region ;;
clipboard | clip) cmd_clipboard ;;
*)
  echo "usage: depot-upload {file <path>|shot-full|shot-region|clipboard}" >&2
  exit 2
  ;;
esac
