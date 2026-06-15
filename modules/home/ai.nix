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
      default = "${config.home.homeDirectory}/ai.md";
      description = "Path to a local checkout of the ai.md repo. If it is not present, wiring is skipped.";
    };

    skillTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "${config.home.homeDirectory}/.agents/skills" # Zed
        "${config.home.homeDirectory}/.claude/skills" # Claude Code
        "${config.home.homeDirectory}/.claude-personal/skills" # Claude Code (personal)
        "${config.home.homeDirectory}/.claude-work/skills" # Claude Code (work)
        "${config.home.homeDirectory}/.claude-vera/skills" # Claude Code (vera)
      ];
      description = "Global skills directories to symlink each ai.md skill into.";
    };

    claudeRulesImports = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "AGENTS.md"
        "rules/voice.md"
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
        "${config.home.homeDirectory}/.claude"
        "${config.home.homeDirectory}/.claude-personal"
        "${config.home.homeDirectory}/.claude-work"
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
