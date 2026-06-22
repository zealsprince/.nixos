{
  config,
  lib,
  ...
}:

let
  cfg = config.my.home.ai;
  # Every skills dir any bucket links into, deduped. Used to prune stale links.
  allSkillDirs = lib.unique (lib.concatLists (lib.attrValues cfg.skillBuckets));
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
      default = "${config.home.homeDirectory}/ai.md";
      description = "Path to a local checkout of the ai.md repo. If it is not present, wiring is skipped.";
    };

    # Skills live in buckets (subfolders of skills/). Each bucket links into a
    # different set of tool config dirs, so personal skills never leak into the
    # work account and vice versa:
    #   shared/   -> everywhere
    #   personal/ -> Zed (personal) + the personal/vera Claude configs
    #   work/     -> the DEFAULT Claude config (~/.claude), which is the work
    #                account that the bare `claude` command and VSCode use.
    skillBuckets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default =
        let
          h = config.home.homeDirectory;
        in
        {
          shared = [
            "${h}/.agents/skills" # Zed (personal)
            "${h}/.claude/skills" # Claude Code default = work (VSCode)
            "${h}/.claude-personal/skills"
            "${h}/.claude-vera/skills"
          ];
          personal = [
            "${h}/.agents/skills" # Zed = personal
            "${h}/.claude-personal/skills"
            "${h}/.claude-vera/skills"
          ];
          work = [
            "${h}/.claude/skills" # default config = work account
          ];
        };
      description = "Map of skills/<bucket> subfolder -> skills dirs to symlink that bucket's skills into.";
    };

    claudeRulesImports = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "AGENTS.md"
        "rules/voice.md"
        "rules/git.md"
      ];
      description = "Rule files (relative to repoPath) to '@import' from CLAUDE.md as always-on context.";
    };

    zedConfigDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/zed";
      description = "Zed config directory where AGENTS.md is symlinked.";
    };

    claudeConfigDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "${config.home.homeDirectory}/.claude" # default = work account (VSCode + bare `claude`)
        "${config.home.homeDirectory}/.claude-personal"
        "${config.home.homeDirectory}/.claude-vera"
      ];
      description = "Claude config directories to write CLAUDE.md rule imports into.";
    };

    veraConfigDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.claude-vera";
      description = "Claude config dir for the Vera profile (launched via `claude-vera`).";
    };

    veraImports = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "VERA.md" ];
      description = ''
        Extra rule files (relative to repoPath) imported as always-on context
        into veraConfigDir only. This is what makes Vera on by default in that
        profile instead of an on-demand `/you` skill.
      '';
    };

    acpPackage = lib.mkOption {
      type = lib.types.str;
      default = "@agentclientprotocol/claude-agent-acp@0.45.0";
      description = ''
        npm package (pinned) for the Claude ACP adapter used by the Zed
        agent_servers. The activation step rewrites any older adapter in the
        Zed settings.json to this value, so the package identity lives here
        while the dotfiles seed owns the rest of the agent_servers block.
      '';
    };

    zedSettingsFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/zed/settings.json";
      description = "Zed settings.json whose Claude ACP adapter package is pinned to acpPackage.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation.linkAiMd = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      repo="${cfg.repoPath}"
      skills_src="$repo/skills"

      if [ ! -d "$repo" ]; then
        echo "ai.md: no checkout at $repo; skipping wiring."
      else
        # 1. Symlink each skill into its bucket's target dirs.
        if [ -d "$skills_src" ]; then
          # First prune any links we previously made (symlinks pointing into
          # this repo's skills tree) so skills that moved buckets or were
          # deleted don't linger. Real dirs and foreign symlinks are left alone.
          for target in ${lib.escapeShellArgs allSkillDirs}; do
            [ -d "$target" ] || continue
            for link in "$target"/*; do
              [ -L "$link" ] || continue
              case "$(readlink "$link")" in
                "$skills_src"/*) rm -f "$link" ;;
              esac
            done
          done

          # Then (re)link each bucket into its targets.
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (bucket: targets: ''
              bucket_src="$skills_src/${bucket}"
              if [ -d "$bucket_src" ]; then
                for target in ${lib.escapeShellArgs targets}; do
                  mkdir -p "$target"
                  for skill in "$bucket_src"/*/; do
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
              fi
            '') cfg.skillBuckets
          )}
        else
          echo "ai.md: $skills_src missing; skipping skill links."
        fi

        # 2. Symlink AGENTS.md into the Zed config directory.
        agents_md="$repo/AGENTS.md"
        zed_agents="${cfg.zedConfigDir}/AGENTS.md"
        if [ -f "$agents_md" ]; then
          mkdir -p "${cfg.zedConfigDir}"
          if [ -e "$zed_agents" ] && [ ! -L "$zed_agents" ]; then
            echo "ai.md: skip $zed_agents (exists and is not a symlink)"
          else
            ln -sfn "$agents_md" "$zed_agents"
          fi
        else
          echo "ai.md: $agents_md missing; skipping Zed AGENTS.md link."
        fi

        # 3. Add always-on rule imports to CLAUDE.md in every Claude config dir.
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

        # 3b. Vera profile: import the persona as always-on context so the
        #     `claude-vera` wrapper boots as Vera without invoking `/you`.
        vera_md="${cfg.veraConfigDir}/CLAUDE.md"
        for rel in ${lib.escapeShellArgs cfg.veraImports}; do
          rule="$repo/$rel"
          if [ ! -f "$rule" ]; then
            echo "ai.md: vera import $rule missing; skipping."
            continue
          fi
          mkdir -p "${cfg.veraConfigDir}"
          touch "$vera_md"
          line="@$rule"
          if ! grep -qxF "$line" "$vera_md"; then
            printf '%s\n' "$line" >> "$vera_md"
            echo "ai.md: added vera import $line to $vera_md"
          fi
        done
      fi

      # 5. Pin the Claude ACP adapter package in the Zed settings.json. This is
      #    independent of the ai.md checkout: the dotfiles seed owns the
      #    agent_servers structure, ai.nix owns just the adapter identity.
      #    Rewrites the legacy adapter and any other-versioned new adapter to
      #    the pinned value. Idempotent.
      zed_settings="${cfg.zedSettingsFile}"
      acp_pkg="${cfg.acpPackage}"
      if [ -f "$zed_settings" ]; then
        if grep -q '@zed-industries/claude-code-acp\|@agentclientprotocol/claude-agent-acp' "$zed_settings"; then
          tmp=$(mktemp)
          sed -E \
            -e "s#@zed-industries/claude-code-acp(@[^\"]*)?#$acp_pkg#g" \
            -e "s#@agentclientprotocol/claude-agent-acp(@[^\"]*)?#$acp_pkg#g" \
            "$zed_settings" > "$tmp"
          if ! cmp -s "$zed_settings" "$tmp"; then
            cp "$tmp" "$zed_settings"
            echo "ai.md: pinned Zed ACP adapter to $acp_pkg in $zed_settings"
          fi
          rm -f "$tmp"
        fi
      else
        echo "ai.md: $zed_settings missing; skipping ACP adapter pin."
      fi
    '';
  };
}
