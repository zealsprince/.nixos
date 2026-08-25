# serve-ai-external: the local model servers, headless, weights on the SSD.
#
# One command rather than a wrapper per tool. `ollama`, `draw-things-cli` and
# the ComfyUI venv are fine as they are, and the environment already points them
# at the same root (OLLAMA_MODELS, DRAWTHINGS_MODELS_DIR, both set by
# ../ai-external.nix), so `ollama pull llava` lands on the SSD with nothing in
# the way.
#
# What has no native equivalent is starting these three headless with the right
# arguments and knowing whether they're up. gRPCServerCLI in particular takes
# its models directory, port, weight cache and TLS as positional and flag
# arguments with no config file anywhere, so something has to hold them.
#
# Everything is deliberately headless. The GUI apps can exist, they just aren't
# in the loop: Ollama.app binds the port and then stops answering requests.

set -euo pipefail

ROOT="${EXTERNAL_AI_ROOT:-$AI_ROOT_DEFAULT}"
ALL="ollama drawthings comfyui"

usage() {
  cat <<EOF
usage: serve-ai-external <command> [service...]

  start [service...]     start all three, or only the ones named
  stop [service...]
  restart [service...]
  status                 what's running, where, and what it costs on disk
  logs <service> [-f]

services: $ALL
root:     $ROOT (override with EXTERNAL_AI_ROOT)
EOF
}

die() { echo "serve-ai-external: $1" >&2; exit 1; }

# The refusal is the point of this whole thing. Every one of these tools falls
# back to somewhere on the internal disk when its models directory isn't there,
# and you find out days later when tens of gigabytes turn up at home.
need_root() {
  if [ ! -d "$ROOT" ]; then
    die "no model root at $ROOT. Is the SSD mounted?"
  fi
  mkdir -p "$ROOT/logs" "$ROOT/run"
}

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "$1 isn't on PATH. $2"
  fi
}

known() {
  case " $ALL " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

log_of() { echo "$ROOT/logs/$1.log"; }
pidfile_of() { echo "$ROOT/run/$1.pid"; }

pid_of() {
  local f
  f="$(pidfile_of "$1")"
  if [ -f "$f" ]; then cat "$f"; fi
}

running() {
  local p
  p="$(pid_of "$1")"
  if [ -z "$p" ]; then return 1; fi
  kill -0 "$p" 2>/dev/null
}

models_of() {
  case "$1" in
    ollama) echo "$ROOT/ollama/models" ;;
    drawthings) echo "$ROOT/drawthings/models" ;;
    comfyui) echo "$COMFYUI_MODELS_DEFAULT" ;;
  esac
}

# Whether anything at all holds a port, which is not the same question as
# whether this script started it. The Comfy Desktop app drives the same install
# behind my back, and its instance has no pidfile here.
port_busy() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && exec 3>&-
}

# Records the pid and confirms the thing survived its first second, so a server
# that dies on startup says why instead of vanishing. Everything it prints goes
# to its log.
track() {
  local svc=$1 p=$2
  echo "$p" >"$(pidfile_of "$svc")"
  sleep 1
  if ! running "$svc"; then
    die "$svc failed to start. Last lines of $(log_of "$svc"):
$(tail -n 5 "$(log_of "$svc")" 2>/dev/null)"
  fi
  echo "$svc started (pid $p)"
}

start_one() {
  local svc=$1 log models
  if running "$svc"; then
    echo "$svc already running (pid $(pid_of "$svc"))"
    return 0
  fi

  need_root
  log="$(log_of "$svc")"
  models="$(models_of "$svc")"

  case "$svc" in
    ollama)
      need_command ollama "Install Ollama, or put its binary on PATH."
      mkdir -p "$models"
      OLLAMA_MODELS="$models" OLLAMA_HOST="$OLLAMA_HOST_DEFAULT" \
        nohup ollama serve >>"$log" 2>&1 &
      track "$svc" $!
      ;;

    drawthings)
      need_command gRPCServerCLI-macOS "Install the Draw Things gRPC server."
      mkdir -p "$models"
      # Plaintext unless told otherwise, because that's what a local server is
      # for. A client's own TLS setting has to agree with whatever this is.
      set -- "$models" -p "$DRAWTHINGS_PORT_DEFAULT" -w "$DRAWTHINGS_CACHE_DEFAULT"
      if [ "$DRAWTHINGS_TLS_DEFAULT" != "1" ]; then
        set -- "$@" --no-tls
      fi
      nohup gRPCServerCLI-macOS "$@" >>"$log" 2>&1 &
      track "$svc" $!
      ;;

    comfyui)
      # The Comfy Desktop layout: the install root holds the interpreter in
      # standalone-env/, and the checkout with its .venv one level down.
      local tree="$ROOT/comfyui/ComfyUI" py="$ROOT/comfyui/ComfyUI/.venv/bin/python"
      if [ ! -x "$py" ]; then
        die "no ComfyUI interpreter at $py. Install ComfyUI through the Desktop app,
pointing it at $ROOT/comfyui."
      fi
      # The Desktop app can have started this same install, in which case it
      # owns the port, the workflow database and the user directory, and a
      # second server would fight it for all three.
      if port_busy "$COMFYUI_PORT_DEFAULT"; then
        die "something already holds port $COMFYUI_PORT_DEFAULT, most likely the Comfy Desktop app.
Quit it before starting ComfyUI headless."
      fi
      mkdir -p "$COMFYUI_INPUT_DEFAULT" "$COMFYUI_OUTPUT_DEFAULT"
      # Models come from ComfyUI/extra_model_paths.yaml, which main.py reads by
      # itself. Input and output have no such file, so they're passed here and
      # have to match what the Desktop app has in its settings.json.
      # exec so the recorded pid is the server rather than the subshell.
      # shellcheck disable=SC2086
      ( cd "$tree" && exec nohup "$py" main.py \
          --listen 127.0.0.1 --port "$COMFYUI_PORT_DEFAULT" \
          --input-directory "$COMFYUI_INPUT_DEFAULT" \
          --output-directory "$COMFYUI_OUTPUT_DEFAULT" \
          $COMFYUI_EXTRA_ARGS_DEFAULT ) >>"$log" 2>&1 &
      track "$svc" $!
      ;;
  esac
}

stop_one() {
  local svc=$1 p
  if ! running "$svc"; then
    rm -f "$(pidfile_of "$svc")"
    # Killing the Desktop app's server out from under it would leave the app
    # sitting there pointed at nothing, so say who has it and stop.
    if [ "$svc" = comfyui ] && port_busy "$COMFYUI_PORT_DEFAULT"; then
      echo "$svc is running under the Desktop app. Quit the app to stop it."
      return 0
    fi
    echo "$svc isn't running"
    return 0
  fi
  p="$(pid_of "$svc")"
  kill "$p" 2>/dev/null || true
  for _ in $(seq 1 20); do
    if ! kill -0 "$p" 2>/dev/null; then break; fi
    sleep 0.5
  done
  kill -9 "$p" 2>/dev/null || true
  rm -f "$(pidfile_of "$svc")"
  echo "$svc stopped"
}

# Size on disk answers the question you actually have when you're deciding what
# to delete.
status_one() {
  local svc=$1 models
  models="$(models_of "$svc")"

  if running "$svc"; then
    echo "$svc: running (pid $(pid_of "$svc"))"
  elif [ "$svc" = comfyui ] && port_busy "$COMFYUI_PORT_DEFAULT"; then
    # Same install, different launcher. Saying "stopped" here would be a lie,
    # and it's the answer I need before I try to start it myself.
    echo "$svc: running under the Desktop app, not this script"
  else
    echo "$svc: stopped"
  fi

  echo "  models: $models"
  if [ -d "$models" ]; then
    echo "  on disk: $(du -sh "$models" 2>/dev/null | cut -f1)"
  else
    echo "  on disk: missing"
  fi

  if [ "$svc" = comfyui ]; then
    echo "  input: $COMFYUI_INPUT_DEFAULT"
    echo "  output: $COMFYUI_OUTPUT_DEFAULT"
  fi

  # ComfyUI reports whenever the port answers, since the Desktop app's instance
  # is just as real as one this script started.
  if running "$svc" || { [ "$svc" = comfyui ] && port_busy "$COMFYUI_PORT_DEFAULT"; }; then
    case "$svc" in
      ollama)
        echo "  api: $(curl -s --max-time 3 "http://$OLLAMA_HOST_DEFAULT/api/version" || echo "not answering")"
        ;;
      drawthings)
        echo "  port: $DRAWTHINGS_PORT_DEFAULT, tls: $DRAWTHINGS_TLS_DEFAULT, weights cache: ${DRAWTHINGS_CACHE_DEFAULT}GiB"
        ;;
      comfyui)
        if curl -s --max-time 3 "http://127.0.0.1:$COMFYUI_PORT_DEFAULT/system_stats" >/dev/null; then
          echo "  url: http://127.0.0.1:$COMFYUI_PORT_DEFAULT (answering)"
        else
          echo "  url: http://127.0.0.1:$COMFYUI_PORT_DEFAULT (not answering)"
        fi
        ;;
    esac
  fi
}

CMD="${1:-status}"
if [ $# -gt 0 ]; then shift; fi

# Remaining arguments name services; no arguments means all of them.
for svc in "$@"; do
  if ! known "$svc"; then
    die "unknown service '$svc'. Try: $ALL"
  fi
done
TARGETS="$*"
if [ -z "$TARGETS" ]; then TARGETS="$ALL"; fi

case "$CMD" in
  start)
    for svc in $TARGETS; do start_one "$svc"; done
    ;;
  stop)
    for svc in $TARGETS; do stop_one "$svc"; done
    ;;
  restart)
    for svc in $TARGETS; do stop_one "$svc"; done
    for svc in $TARGETS; do start_one "$svc"; done
    ;;
  status)
    if [ ! -d "$ROOT" ]; then
      die "no model root at $ROOT. Is the SSD mounted?"
    fi
    echo "root: $ROOT ($(df -h "$ROOT" | tail -1 | awk '{print $4}') free)"
    echo
    for svc in $TARGETS; do status_one "$svc"; done
    ;;
  logs)
    svc="${1:-}"
    if ! known "$svc"; then die "logs needs a service: $ALL"; fi
    log="$(log_of "$svc")"
    if [ ! -f "$log" ]; then die "no log at $log yet"; fi
    if [ "${2:-}" = "-f" ]; then tail -f "$log"; else tail -n 40 "$log"; fi
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
