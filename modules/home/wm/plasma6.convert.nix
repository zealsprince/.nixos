{
  config,
  pkgs,
  lib,
  ...
}:

# Dolphin "Convert To" service menus.
#
# Adds a right-click submenu to Dolphin (and any KIO file view) that converts the
# selected files into another format, writing the result next to the source.
# Images go through ImageMagick, audio/video through ffmpeg.
#
# Sibling of `plasma6.nix`, which owns autostart/shortcuts. Kept separate so the
# format catalogue stays readable.

let
  cfg = config.my.home.wm.plasma6.convert;

  # ---------------------------------------------------------------------------
  # Format catalogues
  #
  # Each entry declares the output extension, the menu label, and the shell body
  # that does the work. `$1` is the source file, `$2` the destination.
  #
  # IMPORTANT: These are Nix multiline strings. Shell `${...}` sequences must be
  # escaped as `''${...}`; plain `$1`/`$2` are fine.
  # ---------------------------------------------------------------------------
  q = toString cfg.image.quality;
  crf = toString cfg.video.crf;
  rate = cfg.audio.bitrate;

  ffmpeg = ''ffmpeg -nostdin -y -i "$1"'';

  imageFormats = {
    jpg = {
      ext = "jpg";
      label = "JPEG";
      # JPEG has no alpha channel, so composite transparency onto white first.
      cmd = ''magick "$1" -auto-orient -background white -alpha remove -alpha off -quality ${q} "$2"'';
    };
    png = {
      ext = "png";
      label = "PNG";
      cmd = ''magick "$1" -auto-orient -define png:compression-level=9 "$2"'';
    };
    webp = {
      ext = "webp";
      label = "WebP";
      cmd = ''magick "$1" -auto-orient -quality ${q} "$2"'';
    };
    avif = {
      ext = "avif";
      label = "AVIF";
      cmd = ''magick "$1" -auto-orient -quality ${q} "$2"'';
    };
    heic = {
      ext = "heic";
      label = "HEIC";
      cmd = ''magick "$1" -auto-orient -quality ${q} "$2"'';
    };
    jxl = {
      ext = "jxl";
      label = "JPEG XL";
      cmd = ''magick "$1" -auto-orient -quality ${q} "$2"'';
    };
    tiff = {
      ext = "tiff";
      label = "TIFF";
      cmd = ''magick "$1" -auto-orient -compress lzw "$2"'';
    };
    bmp = {
      ext = "bmp";
      label = "BMP";
      cmd = ''magick "$1" -auto-orient "$2"'';
    };
    gif = {
      ext = "gif";
      label = "GIF";
      cmd = ''magick "$1" -auto-orient "$2"'';
    };
    ico = {
      ext = "ico";
      label = "Icon (ICO)";
      cmd = ''magick "$1" -auto-orient -resize 256x256 "$2"'';
    };
    pdf = {
      ext = "pdf";
      label = "PDF";
      cmd = ''magick "$1" -auto-orient "$2"'';
    };
  };

  videoFormats = {
    mp4 = {
      ext = "mp4";
      label = "MP4 (H.264)";
      cmd = ''${ffmpeg} -c:v libx264 -crf ${crf} -preset medium -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart "$2"'';
    };
    mkv = {
      ext = "mkv";
      label = "Matroska (remux)";
      # Container swap only, streams are copied as-is.
      cmd = ''${ffmpeg} -c copy "$2"'';
    };
    webm = {
      ext = "webm";
      label = "WebM (VP9)";
      cmd = ''${ffmpeg} -c:v libvpx-vp9 -crf 32 -b:v 0 -row-mt 1 -c:a libopus -b:a 128k "$2"'';
    };
    gif = {
      ext = "gif";
      label = "GIF";
      cmd = ''${ffmpeg} -vf "fps=15,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" -loop 0 "$2"'';
    };
    mp3 = {
      ext = "mp3";
      label = "MP3 (audio only)";
      cmd = ''${ffmpeg} -vn -c:a libmp3lame -b:a ${rate} "$2"'';
    };
  };

  audioFormats = {
    mp3 = {
      ext = "mp3";
      label = "MP3";
      cmd = ''${ffmpeg} -vn -c:a libmp3lame -b:a ${rate} "$2"'';
    };
    flac = {
      ext = "flac";
      label = "FLAC";
      cmd = ''${ffmpeg} -vn -c:a flac "$2"'';
    };
    wav = {
      ext = "wav";
      label = "WAV";
      cmd = ''${ffmpeg} -vn -c:a pcm_s16le "$2"'';
    };
    opus = {
      ext = "opus";
      label = "Opus";
      cmd = ''${ffmpeg} -vn -c:a libopus -b:a 192k "$2"'';
    };
    m4a = {
      ext = "m4a";
      label = "M4A (AAC)";
      cmd = ''${ffmpeg} -vn -c:a aac -b:a 256k "$2"'';
    };
    ogg = {
      ext = "ogg";
      label = "Ogg Vorbis";
      cmd = ''${ffmpeg} -vn -c:a libvorbis -q:a 6 "$2"'';
    };
  };

  kinds = {
    image = {
      catalog = imageFormats;
      icon = "image-x-generic";
    };
    video = {
      catalog = videoFormats;
      icon = "video-x-generic";
    };
    audio = {
      catalog = audioFormats;
      icon = "audio-x-generic";
    };
  };

  # Preset id as seen on the command line and in the service menu action name,
  # e.g. "image-jpg". Desktop Action names are restricted to [A-Za-z0-9-].
  presetId = kind: id: "${kind}-${id}";

  # One case branch per preset. `run` is redefined per branch so the loop body
  # below stays format-agnostic.
  mkCase =
    kind: id: fmt:
    ''
      ${presetId kind id})
        out_ext="${fmt.ext}"
        run() { ${fmt.cmd}; }
        ;;
    '';

  cases = lib.concatStrings (
    lib.mapAttrsToList (
      kind: k: lib.concatStrings (lib.mapAttrsToList (mkCase kind) k.catalog)
    ) kinds
  );

  convert = pkgs.writeShellScriptBin "plasma-convert" ''
    set -eu

    export PATH=${
      lib.makeBinPath [
        pkgs.imagemagick
        pkgs.ffmpeg-full
        pkgs.coreutils
        pkgs.libnotify
      ]
    }:$PATH

    preset="''${1:-}"
    [ -n "$preset" ] || exit 1
    shift
    [ "$#" -gt 0 ] || exit 0

    case "$preset" in
      image-*) icon="image-x-generic" ;;
      video-*) icon="video-x-generic" ;;
      audio-*) icon="audio-x-generic" ;;
      *) icon="dialog-error" ;;
    esac

    # All notifications share a synchronous hint so progress updates replace each
    # other instead of stacking up one popup per file.
    notify() {
      notify-send -a "Convert" -i "$icon" \
        -h "string:x-canonical-private-synchronous:plasma-convert" \
        "$1" "''${2:-}" || true
    }

    case "$preset" in
    ${cases}
      *)
        icon="dialog-error"
        notify "Convert failed" "Unknown target format: $preset"
        exit 1
        ;;
    esac

    state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}"
    mkdir -p "$state_dir"
    log="$state_dir/plasma-convert.log"

    total=$#
    index=0
    ok=0
    failed=0
    skipped=0

    for src in "$@"; do
      index=$((index + 1))

      dir="$(dirname "$src")"
      name="$(basename "$src")"
      case "$name" in
        *.*) stem="''${name%.*}"; src_ext="''${name##*.}" ;;
        *) stem="$name"; src_ext="" ;;
      esac

      # Already in the target format, nothing worth doing.
      if [ "$(printf '%s' "$src_ext" | tr '[:upper:]' '[:lower:]')" = "$out_ext" ]; then
        skipped=$((skipped + 1))
        continue
      fi

      # Never clobber an existing file: name.jpg, name-1.jpg, name-2.jpg, ...
      out="$dir/$stem.$out_ext"
      n=1
      while [ -e "$out" ]; do
        out="$dir/$stem-$n.$out_ext"
        n=$((n + 1))
      done

      notify "Converting $index of $total" "$name"

      printf '\n=== %s\n%s -> %s\n' "$(date -Iseconds)" "$src" "$out" >>"$log"

      if run "$src" "$out" >>"$log" 2>&1; then
        ok=$((ok + 1))
      else
        failed=$((failed + 1))
        rm -f "$out"
      fi
    done

    if [ "$failed" -gt 0 ]; then
      icon="dialog-error"
      notify "Converted $ok of $total, $failed failed" "Details in $log"
      exit 1
    fi

    if [ "$skipped" -gt 0 ]; then
      notify "Converted $ok of $total" "$skipped already in $out_ext format"
      exit 0
    fi

    notify "Converted $ok of $total to $out_ext"
  '';

  mkServiceMenu =
    {
      kind,
      formats,
      mimeTypes,
    }:
    let
      inherit (kinds.${kind}) catalog icon;
      chosen = map (id: catalog.${id} // { inherit id; }) formats;
    in
    ''
      [Desktop Entry]
      Type=Service
      X-KDE-ServiceTypes=KonqPopupMenu/Plugin
      MimeType=${lib.concatMapStrings (m: "${m};") mimeTypes}
      Actions=${lib.concatMapStringsSep ";" (f: presetId kind f.id) chosen}
      X-KDE-Submenu=${cfg.submenu}
      Icon=${icon}

      ${lib.concatMapStringsSep "\n" (f: ''
        [Desktop Action ${presetId kind f.id}]
        Name=${f.label}
        Icon=${icon}
        Exec=${convert}/bin/plasma-convert ${presetId kind f.id} %F
      '') chosen}
    '';

  mkFormatsOption =
    {
      catalog,
      default,
      kind,
    }:
    lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames catalog));
      inherit default;
      description = "Target ${kind} formats to offer, in menu order.";
    };

  mkMimeOption =
    default:
    lib.mkOption {
      type = lib.types.listOf lib.types.str;
      inherit default;
      description = "MIME types the menu attaches to. The `*/*` wildcard covers most cases; the explicit entries are there for KIO builds that don't expand it.";
    };

in
{
  options.my.home.wm.plasma6.convert = {
    enable = lib.mkEnableOption "Dolphin right-click file conversion service menus";

    submenu = lib.mkOption {
      type = lib.types.str;
      default = "Convert To";
      description = "Submenu label shown in the Dolphin context menu.";
    };

    image = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Offer image conversion (ImageMagick).";
      };

      quality = lib.mkOption {
        type = lib.types.ints.between 1 100;
        default = 92;
        description = "Quality passed to lossy image encoders (JPEG, WebP, AVIF, HEIC, JXL).";
      };

      formats = mkFormatsOption {
        catalog = imageFormats;
        kind = "image";
        default = [
          "jpg"
          "png"
          "webp"
          "avif"
          "heic"
          "tiff"
          "pdf"
        ];
      };

      mimeTypes = mkMimeOption [
        "image/*"
        "image/jpeg"
        "image/png"
        "image/webp"
        "image/heif"
        "image/heic"
        "image/avif"
        "image/jxl"
        "image/tiff"
        "image/bmp"
        "image/gif"
        "image/x-icon"
        "image/vnd.microsoft.icon"
        "image/x-portable-pixmap"
      ];
    };

    video = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Offer video conversion (ffmpeg).";
      };

      crf = lib.mkOption {
        type = lib.types.ints.between 0 51;
        default = 20;
        description = "x264 CRF used for MP4 output. Lower is bigger and better.";
      };

      formats = mkFormatsOption {
        catalog = videoFormats;
        kind = "video";
        default = [
          "mp4"
          "mkv"
          "webm"
          "gif"
          "mp3"
        ];
      };

      mimeTypes = mkMimeOption [
        "video/*"
        "video/mp4"
        "video/x-matroska"
        "video/quicktime"
        "video/webm"
        "video/x-msvideo"
        "video/mpeg"
        "video/x-ms-wmv"
        "video/x-flv"
        "video/3gpp"
        "video/ogg"
        "video/x-m4v"
      ];
    };

    audio = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Offer audio conversion (ffmpeg).";
      };

      bitrate = lib.mkOption {
        type = lib.types.str;
        default = "320k";
        description = "Bitrate used for MP3 output.";
      };

      formats = mkFormatsOption {
        catalog = audioFormats;
        kind = "audio";
        default = [
          "mp3"
          "flac"
          "wav"
          "opus"
          "m4a"
        ];
      };

      mimeTypes = mkMimeOption [
        "audio/*"
        "audio/mpeg"
        "audio/flac"
        "audio/x-flac"
        "audio/wav"
        "audio/x-wav"
        "audio/ogg"
        "audio/opus"
        "audio/mp4"
        "audio/x-m4a"
        "audio/aac"
        "audio/x-aiff"
        "audio/x-ms-wma"
        "audio/webm"
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    # `plasma-convert` on PATH so the same conversions are available from a shell.
    home.packages = [ convert ];

    home.file = lib.mkMerge [
      (lib.mkIf (cfg.image.enable && cfg.image.formats != [ ]) {
        ".local/share/kio/servicemenus/convert-image.desktop".text = mkServiceMenu {
          kind = "image";
          formats = cfg.image.formats;
          mimeTypes = cfg.image.mimeTypes;
        };
      })

      (lib.mkIf (cfg.video.enable && cfg.video.formats != [ ]) {
        ".local/share/kio/servicemenus/convert-video.desktop".text = mkServiceMenu {
          kind = "video";
          formats = cfg.video.formats;
          mimeTypes = cfg.video.mimeTypes;
        };
      })

      (lib.mkIf (cfg.audio.enable && cfg.audio.formats != [ ]) {
        ".local/share/kio/servicemenus/convert-audio.desktop".text = mkServiceMenu {
          kind = "audio";
          formats = cfg.audio.formats;
          mimeTypes = cfg.audio.mimeTypes;
        };
      })
    ];
  };
}
