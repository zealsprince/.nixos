{
  config,
  lib,
  ...
}:

let
  cfg = config.my.home.ai;
in
{
  # ---------------------------------------------------------------------------
  # ai.md wiring (skills + rules shared across AI tools)
  #
  # `ai.md` is a PRIVATE repo, so it is deliberately NOT a flake input: that
  # would make every `nix` eval/build try to fetch it, and fail on any machine
  # without access. Instead we link a *local checkout* at activation time and
  # quietly skip the whole thing when the checkout is not present. Nothing here
  # can break a rebuild if the repo is missing.
  #
  # Skills are symlinked into each tool's global skills directory; the repo
  # stays the single source of truth and edits are picked up live (no rebuild).
  # ---------------------------------------------------------------------------
  options.my.home.ai = {
    enable = lib.mkEnableOption "ai.md skills/rules wiring" // {
      default = true;
    };

    repoPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Projects/zealsprince/ai.md";
      description = "Path to a local checkout of the ai.md repo. If it is not present, wiring is skipped.";
    };

    skillTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "${config.home.homeDirectory}/.agents/skills" # Zed
        "${config.home.homeDirectory}/.claude/skills" # Claude Code
      ];
      description = "Global skills directories to symlink each ai.md skill into.";
    };

    claudeRulesImports = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "rules/voice.md" ];
      description = "Rule files (relative to repoPath) to '@import' from CLAUDE.md as always-on context.";
    };

    claudeConfigDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "${config.home.homeDirectory}/.claude"
        "${config.home.homeDirectory}/.claude-personal"
        "${config.home.homeDirectory}/.claude-work"
      ];
      description = "Claude config directories to write CLAUDE.md rule imports into.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation.linkAiMd = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      repo="${cfg.repoPath}"
      skills_src="$repo/skills"

      if [ ! -d "$repo" ]; then
        echo "ai.md: no checkout at $repo; skipping wiring."
      else
        # 1. Symlink each skill folder into every target skills directory.
        if [ -d "$skills_src" ]; then
          for target in ${lib.escapeShellArgs cfg.skillTargets}; do
            mkdir -p "$target"
            for skill in "$skills_src"/*/; do
              [ -d "$skill" ] || continue
              name=$(basename "$skill")
              link="$target/$name"

              # Don't clobber a real directory that isn't one of our symlinks.
              if [ -e "$link" ] && [ ! -L "$link" ]; then
                echo "ai.md: skip $link (exists and is not a symlink)"
                continue
              fi

              ln -sfn "$skill" "$link"
            done
          done
        else
          echo "ai.md: $skills_src missing; skipping skill links."
        fi

        # 2. Add always-on rule imports to CLAUDE.md in every Claude config dir.
        for claude_dir in ${lib.escapeShellArgs cfg.claudeConfigDirs}; do
          claude_md="$claude_dir/CLAUDE.md"
          for rel in ${lib.escapeShellArgs cfg.claudeRulesImports}; do
            rule="$repo/$rel"
            if [ ! -f "$rule" ]; then
              echo "ai.md: rule $rule missing; skipping import."
              continue
            fi
            mkdir -p "$claude_dir"
            touch "$claude_md"
            line="@$rule"
            if ! grep -qxF "$line" "$claude_md"; then
              printf '%s\n' "$line" >> "$claude_md"
              echo "ai.md: added import $line to $claude_md"
            fi
          done
        done
      fi
    '';
  };
}
