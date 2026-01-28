{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{


  # ---------------------------------------------------------------------------
  # Crush (via NUR module): user-scoped configuration
  #
  # IMPORTANT:
  # - Do not inline API keys here; that would put secrets into the Nix store.
  # - Instead we read it from the sops-nix-managed secret file at activation time.
  # ---------------------------------------------------------------------------
  programs.crush = {
    enable = true;

    settings = {
      providers = {
        # Ollama (local models)
        #
        # Crush can talk to Ollama via its OpenAI-compatible endpoint.
        # By convention, we present it as an OpenAI provider pointing at localhost.
        #
        # Note:
        # - `api_key` is not required for Ollama, but some OpenAI clients require it to be set.
        # - Model `id`s must match what `ollama list` shows (e.g. `qwen2.5-coder:latest`).
        #
        # Fetch the models via `ollama run <model>`..
        ollama = {
          id = "ollama";
          name = "Ollama";
          base_url = "http://127.0.0.1:11434/v1";
          type = "openai";

          # Dummy value for OpenAI-compatible clients.
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

          # Crush expects the API key value (not a file path).
          # We export OPENAI_API_KEY from the agenix-decrypted file in your shell init below.
          api_key = "$OPENAI_API_KEY";

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

          # Crush expects the API key value (not a file path).
          # We export GEMINI_API_KEY from the agenix-decrypted file in your shell init below.
          api_key = "$GEMINI_API_KEY";

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
  };
}
