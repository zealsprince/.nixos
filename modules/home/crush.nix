{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Template configuration with placeholders for secrets
  baseSettings = {
    providers = {
      ollama = {
        id = "ollama";
        name = "Ollama";
        base_url = "http://127.0.0.1:11434/v1";
        type = "openai";
        api_key = "ollama";
        models = [
          {
            id = "qwen2.5-coder:7b";
            name = "qwen2.5-coder:7b";
          }
          {
            id = "qwen3-vl:8b";
            name = "qwen3-vl:8b";
          }
          {
            id = "devstral-small-2:latest";
            name = "devstral-small-2:latest";
          }
        ];
      };

      openai = {
        id = "openai";
        name = "OpenAI";
        base_url = "https://api.openai.com/v1";
        type = "openai";
        api_key = "@OPENAI_API_KEY@";
        models = [
          {
            id = "gpt-5.2";
            name = "GPT-5.2";
          }
          {
            id = "gpt-5.2-pro";
            name = "GPT-5.2 Pro";
          }
          {
            id = "gpt-5.2-codex";
            name = "GPT-5.2 Codex";
          }
          {
            id = "gpt-5";
            name = "GPT-5";
          }
          {
            id = "gpt-5-mini";
            name = "GPT-5 Mini";
          }
          {
            id = "gpt-5-nano";
            name = "GPT-5 Nano";
          }
          {
            id = "o4-mini";
            name = "GPT-o4 Mini";
          }
        ];
      };

      gemini = {
        id = "gemini";
        name = "Gemini";
        type = "gemini";
        api_key = "@GEMINI_API_KEY@";
        models = [
          {
            id = "gemini-3-pro-preview";
            name = "Gemini 3 Pro Preview";
          }
          {
            id = "gemini-3-flash-preview";
            name = "Gemini 3 Flash Preview";
          }
          {
            id = "gemini-2.5-pro";
            name = "Gemini 2.5 Pro";
          }
          {
            id = "gemini-2.5-flash";
            name = "Gemini 2.5 Flash";
          }
        ];
      };
    };

    options = {
      tui = {
        compact_mode = true;
      };
      debug = false;
    };
  };

  # Generate the JSON template in the Nix store
  jsonFormat = pkgs.formats.json { };
  configFileTemplate = jsonFormat.generate "crush-template.json" baseSettings;

  # Reference the runtime paths of the secrets
  openaiSecret = config.age.secrets."crush-openai-api-key".path;
  geminiSecret = config.age.secrets."crush-gemini-api-key".path;
in
{
  programs.crush = {
    enable = true;

    # Disable the standard settings generation so we can handle it manually
    settings = { };
  };

  # Generate the final config file at activation time using secrets
  home.activation.createCrushConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/crush"

    if [ -f "${openaiSecret}" ] && [ -f "${geminiSecret}" ]; then
      OPENAI_KEY=$(cat "${openaiSecret}")
      GEMINI_KEY=$(cat "${geminiSecret}")

      # Replace placeholders with actual keys
      # using | as delimiter to assume keys don't contain pipes
      cat "${configFileTemplate}" \
        | sed "s|@OPENAI_API_KEY@|$OPENAI_KEY|g" \
        | sed "s|@GEMINI_API_KEY@|$GEMINI_KEY|g" \
        > "$HOME/.config/crush/crush.json"

      chmod 600 "$HOME/.config/crush/crush.json"
    else
      echo "WARNING: Crush secrets not found. Skipping config generation."
    fi
  '';
}
