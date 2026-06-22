{
  ...
}:

let
  # Crush supports variable expansion in `api_key` (and other string fields)
  # via its VariableResolver: values like "$VAR" / "${VAR}" are resolved from
  # the environment at runtime. The provider keys are exported from agenix in
  # the zsh init (OPENAI_API_KEY / GEMINI_API_KEY), so we reference them here
  # instead of baking secrets into the generated config.
  settings = {
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
        type = "google";
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
in
{
  programs.crush = {
    enable = true;
    inherit settings;
  };
}
