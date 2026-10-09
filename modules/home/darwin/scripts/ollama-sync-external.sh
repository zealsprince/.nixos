# ollama-sync-external: merge the SSD model archive into the local Ollama store.
#
# Ollama only knows one models directory, so the merge is symlinks: the local
# store is the real one, and whatever the SSD holds gets linked in while it's
# mounted. launchd runs this on every change under /Volumes, and it's
# idempotent, so running it by hand at any point is fine too. A running server
# picks the links up live in both directions; no restart needed.
#
# The cleanup pass comes first and is not optional. One dangling manifest
# symlink makes every ollama command fail outright, and ollama's own startup
# prune leaves such links in place, so unplugging the drive without a cleanup
# breaks ollama until the links are deleted.

set -euo pipefail

STORE="${OLLAMA_LOCAL_STORE:-$OLLAMA_LOCAL_STORE_DEFAULT}"
SSD="${OLLAMA_SSD_STORE:-$OLLAMA_SSD_STORE_DEFAULT}"

mkdir -p "$STORE/manifests" "$STORE/blobs"

# Links whose target is gone, then the empty directories they leave behind.
find "$STORE/manifests" "$STORE/blobs" -type l ! -exec test -e {} \; -delete
find "$STORE/manifests" -mindepth 1 -type d -empty -delete

[ -d "$SSD" ] || exit 0

cd "$SSD"

# The local store wins when both sides have the same model, so a real file is
# never shadowed by a link.
find manifests -type f | while read -r m; do
  if [ ! -e "$STORE/$m" ]; then
    mkdir -p "$STORE/$(dirname "$m")"
    ln -s "$SSD/$m" "$STORE/$m"
  fi
done

find blobs -type f -name 'sha256-*' | while read -r b; do
  [ -e "$STORE/$b" ] || ln -s "$SSD/$b" "$STORE/$b"
done
