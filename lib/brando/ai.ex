defmodule Brando.AI do
  @moduledoc """
  Brando AI integration layer for form input generation.

  This module wraps `ReqLLM` for Brando's admin form AI actions. It resolves model
  and key settings from field options and app config, then performs a per-request
  call to `ReqLLM.generate_text/3`.

  ## App config

      # usually in config/brando.exs
      config :brando, Brando.AI,
        enabled: true,
        default_model: "openai:gpt-4o-mini",
        providers: [
          openai: [api_key: System.get_env("OPENAI_API_KEY")]
        ],
        # Optional per-field defaults
        fields: [
          summary: [prompt: "Summarize title + intro", context: [:title, :intro]]
        ],
        default_opts: [temperature: 0.4]

  ## Resolution order

  - Model: field `:model` -> app `:default_model`
  - API key: field `:api_key` -> provider config `providers[provider][:api_key]` ->
    app `<provider>_api_key` -> `ReqLLM.get_key(:"<provider>_api_key")`
  - Field AI defaults: blueprint `input ... ai: [...]` -> trait-provided defaults ->
    app `fields[field_name]`

  ## Field options

  Besides `:model` and `:api_key`, these options are forwarded to ReqLLM:

  `:temperature`, `:max_tokens`, `:top_p`, `:presence_penalty`,
  `:frequency_penalty`, `:tool_choice`, `:tools`, `:system_prompt`,
  `:provider_options`, `:receive_timeout`, `:thinking_timeout`.

  Note: trait-specific defaults are resolved by each trait through the
  `c:Brando.Trait.ai_field_opts/3` callback. For example, `Brando.Trait.Meta` reads
  field config from `trait :meta, ai: [...]` on the blueprint.
  """

  use Gettext, backend: Brando.Gettext

  alias ReqLLM.Keys
  alias ReqLLM.Response

  @request_opt_keys [
    :temperature,
    :max_tokens,
    :top_p,
    :presence_penalty,
    :frequency_penalty,
    :tool_choice,
    :tools,
    :system_prompt,
    :provider_options,
    :receive_timeout,
    :thinking_timeout
  ]

  def enabled? do
    Keyword.get(config(), :enabled, true)
  end

  def configured?(ai_opts \\ []) do
    ai_opts = normalize_ai_opts(ai_opts)

    with true <- enabled?(),
         {:ok, model} <- resolve_model(ai_opts),
         {:ok, provider} <- provider_from_model(model),
         {:ok, api_key} <- resolve_api_key(provider, ai_opts) do
      api_key != ""
    else
      _ -> false
    end
  end

  @doc """
  Sends `prompt` to the configured model. `prompt` is a string, or a list of
  `ReqLLM.Message`s / a `ReqLLM.Context` when it carries more than text, such
  as an image (`ReqLLM.Message.ContentPart.image/2`).
  """
  def generate_text(prompt, ai_opts \\ []) when is_binary(prompt) or is_list(prompt) or is_struct(prompt) do
    ai_opts = normalize_ai_opts(ai_opts)

    with {:ok, %{model: model, provider: provider, req_opts: req_opts}} <- request(ai_opts),
         {:ok, response} <- ReqLLM.generate_text(model, prompt, req_opts),
         text <- response |> Response.text() |> normalize_text(),
         true <- text != "" or {:error, :empty_response} do
      {:ok,
       %{
         text: text,
         usage: Response.usage(response),
         model: model,
         provider: provider
       }}
    else
      {:error, _} = error -> error
      false -> {:error, :disabled}
      error -> {:error, error}
    end
  end

  @doc """
  Resolve `ai_opts` to a model, its provider and the ReqLLM request options,
  including the API key. For callers that drive ReqLLM themselves, such as the
  content agent's tool loop.
  """
  @spec request(keyword() | map()) ::
          {:ok, %{model: String.t(), provider: atom(), req_opts: keyword()}} | {:error, term()}
  def request(ai_opts \\ []) do
    ai_opts = normalize_ai_opts(ai_opts)

    with true <- enabled?() || {:error, :disabled},
         {:ok, model} <- resolve_model(ai_opts),
         {:ok, provider} <- provider_from_model(model),
         {:ok, api_key} <- resolve_api_key(provider, ai_opts) do
      {:ok, %{model: model, provider: provider, req_opts: build_req_opts(ai_opts, api_key)}}
    end
  end

  @doc """
  What the model `ai_opts` resolve to costs and can read, from ReqLLM's model
  catalogue: `{:ok, %{spec, input_price, output_price, image_input?}}`, prices
  in USD per million tokens and `nil` when the catalogue has none.
  """
  @spec model_info(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def model_info(ai_opts \\ []) do
    with {:ok, spec} <- resolve_model(normalize_ai_opts(ai_opts)),
         {:ok, model} <- ReqLLM.model(spec) do
      cost = Map.get(model, :cost) || %{}
      input_modalities = get_in(Map.get(model, :modalities) || %{}, [:input]) || []

      {:ok,
       %{
         spec: spec,
         provider: model.provider,
         model_id: model.id,
         input_price: cost[:input],
         output_price: cost[:output],
         image_input?: :image in input_modalities
       }}
    end
  rescue
    _ -> {:error, :unknown_model}
  end

  @doc """
  The human name configured for `language`, for prompts that must name it.

  Falls back to the upcased code, which reads well enough in a prompt for a
  language the project never listed.
  """
  @spec language_name(String.t() | atom()) :: String.t()
  def language_name(language) do
    language = to_string(language)

    case Enum.find(Brando.config(:languages) || [], &(&1[:value] == language)) do
      nil -> String.upcase(language)
      config -> config[:text] || String.upcase(language)
    end
  end

  @doc "A message an editor can act on for the errors the AI path returns."
  @spec error_message(term()) :: String.t()
  def error_message(:missing_field), do: gettext("Could not resolve AI settings for this field")
  def error_message(:missing_ai_config), do: gettext("No AI configuration was found for this field")
  def error_message(:missing_prompt), do: gettext("Missing AI prompt configuration")
  def error_message(:missing_model), do: gettext("Missing AI model configuration")
  def error_message(:missing_api_key), do: gettext("Missing API key for selected AI provider")
  def error_message(:empty_response), do: gettext("AI returned an empty response")
  def error_message(:invalid_field_name), do: gettext("Could not update this field from AI response")
  def error_message(:no_context), do: gettext("This entry has no text to describe")
  def error_message(:no_image_input), do: gettext("The configured AI model cannot read images")
  def error_message(:unsupported_format), do: gettext("The image is in a format the AI model cannot read")
  def error_message(:image_file_missing), do: gettext("The image file could not be read")
  def error_message(:invalid_response), do: gettext("The AI reply could not be read")
  def error_message(_), do: gettext("Failed to generate text with AI")

  def normalize_ai_opts(nil), do: []
  def normalize_ai_opts(opts) when is_list(opts), do: opts
  def normalize_ai_opts(opts) when is_map(opts), do: Enum.into(opts, [])
  def normalize_ai_opts(_), do: []

  def field_ai_opts(field_name) when is_atom(field_name), do: field_ai_opts(nil, field_name)

  def field_ai_opts(schema, field_name) when is_atom(field_name) do
    sources = [
      Brando.Trait.get_trait_ai_field_opts(schema, field_name),
      get_field_config(Keyword.get(config(), :fields, %{}), field_name)
    ]

    Enum.find_value(sources, [], fn source ->
      case normalize_ai_opts(source) do
        [] -> nil
        opts -> opts
      end
    end)
  end

  def field_ai_opts(_, _), do: []

  defp build_req_opts(ai_opts, api_key) do
    default_opts = Keyword.get(config(), :default_opts, [])

    request_opts =
      ai_opts
      |> Keyword.take(@request_opt_keys)
      |> Keyword.put(:api_key, api_key)

    Keyword.merge(default_opts, request_opts)
  end

  defp resolve_model(ai_opts) do
    case Keyword.get(ai_opts, :model) || Keyword.get(config(), :default_model) do
      model when is_binary(model) and model != "" ->
        {:ok, model}

      _ ->
        {:error, :missing_model}
    end
  end

  defp provider_from_model(model) when is_binary(model) do
    case String.split(model, ":", parts: 2) do
      [provider, _model_name] ->
        {:ok, String.to_atom(provider)}

      _ ->
        {:error, :invalid_model}
    end
  end

  defp resolve_api_key(provider, ai_opts) do
    case Keyword.get(ai_opts, :api_key) do
      key when is_binary(key) and key != "" ->
        {:ok, key}

      _ ->
        resolve_provider_api_key(provider)
    end
  end

  defp resolve_provider_api_key(provider) do
    provider_key =
      provider
      |> provider_config()
      |> get_provider_api_key()

    key =
      provider_key ||
        Keyword.get(config(), :"#{provider}_api_key") ||
        fallback_req_llm_key(provider)

    case key do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end

  defp provider_config(provider) do
    providers = Keyword.get(config(), :providers, %{})

    case providers do
      map when is_map(map) ->
        Map.get(map, provider) || Map.get(map, Atom.to_string(provider))

      list when is_list(list) ->
        Keyword.get(list, provider)

      _ ->
        nil
    end
  end

  defp get_provider_api_key(nil), do: nil
  defp get_provider_api_key(config) when is_list(config), do: Keyword.get(config, :api_key)
  defp get_provider_api_key(%{api_key: api_key}), do: api_key
  defp get_provider_api_key(%{"api_key" => api_key}), do: api_key
  defp get_provider_api_key(config) when is_map(config), do: nil
  defp get_provider_api_key(_), do: nil

  defp fallback_req_llm_key(provider) do
    provider
    |> Keys.config_key()
    |> ReqLLM.get_key()
  rescue
    _ -> nil
  end

  defp normalize_text(nil), do: ""
  defp normalize_text(text) when is_binary(text), do: String.trim(text)
  defp normalize_text(text), do: text |> to_string() |> String.trim()

  defp get_field_config(config_source, field_name) when is_map(config_source) do
    Map.get(config_source, field_name) || Map.get(config_source, Atom.to_string(field_name))
  end

  defp get_field_config(config_source, field_name) when is_list(config_source) do
    Keyword.get(config_source, field_name)
  end

  defp get_field_config(_, _), do: nil

  defp config do
    Application.get_env(:brando, __MODULE__, [])
  end
end
