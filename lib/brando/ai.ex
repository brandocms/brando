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
        models: [
          default: "anthropic:claude-opus-5-5",
          # Jobs that read images (alt text) use this when it is set
          image: "anthropic:claude-haiku-4-5"
        ],
        providers: [
          anthropic: [api_key: System.get_env("ANTHROPIC_API_KEY")]
        ],
        # Optional per-field defaults
        fields: [
          summary: [prompt: "Summarize title + intro", context: [:title, :intro]],
          meta_description: [model: :default]
        ],
        default_opts: [temperature: 0.4]

  ## Named models

  `models:` names the models a site uses. `:default` does everything unless
  told otherwise; a job that needs something particular asks for a name —
  image jobs ask for `:image`, so a cheaper model that reads images can
  write alt text while a stronger one writes copy. A name that is not
  configured falls back to `:default`. A field's `model:` takes a name or a
  full `"provider:model"` spec. `default_model: "..."` is still read, as
  `models: [default: "..."]`.

  ## Resolution order

  - Model: field `:model` (a spec, or a name in `models:`) -> the job's own
    name (`:image` for alt text) -> `models[:default]` / `:default_model`
  - API key: field `:api_key` -> provider config `providers[provider][:api_key]` ->
    app `<provider>_api_key` -> `ReqLLM.get_key(:"<provider>_api_key")`
  - Field AI defaults: blueprint `input ... ai: [...]` -> trait-provided defaults,
    with app `fields[field_name]` filling in what they leave out (a `model:`, say)

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
         {:ok, provider} <- provider_from_model(spec) do
      {:ok, catalogue_info(spec, provider, LLMDB.model(spec))}
    end
  rescue
    _ -> {:error, :unknown_model}
  end

  # Straight from the catalogue ReqLLM reads, which, unlike ReqLLM.model/1,
  # answers a model it does not know without a warning per lookup. Outside the
  # catalogue nothing is known: no prices, and image input nil.
  defp catalogue_info(spec, _provider, {:ok, model}) do
    cost = Map.get(model, :cost) || %{}

    %{
      spec: spec,
      provider: model.provider,
      model_id: model.id,
      input_price: cost[:input],
      output_price: cost[:output],
      image_input?: image_input?(model.modalities)
    }
  end

  defp catalogue_info(spec, provider, _not_found) do
    [_provider, model_id] = String.split(spec, ":", parts: 2)
    %{spec: spec, provider: provider, model_id: model_id, input_price: nil, output_price: nil, image_input?: nil}
  end

  # nil, not false, for a model outside the catalogue: whether it reads images
  # is unknown then, and a new model usually does.
  defp image_input?(%{input: inputs}) when is_list(inputs), do: :image in inputs
  defp image_input?(_modalities), do: nil

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

  def error_message(:unknown_model),
    do: gettext("The configured AI model is not in the model catalogue, so its price and abilities are unknown")

  def error_message(:unsupported_format), do: gettext("The image is in a format the AI model cannot read")
  def error_message(:image_file_missing), do: gettext("The image file could not be read")
  def error_message(:invalid_response), do: gettext("The AI reply could not be read")
  def error_message(_), do: gettext("Failed to generate text with AI")

  def normalize_ai_opts(nil), do: []
  def normalize_ai_opts(opts) when is_list(opts), do: opts
  def normalize_ai_opts(opts) when is_map(opts), do: Enum.into(opts, [])
  def normalize_ai_opts(_), do: []

  def field_ai_opts(field_name) when is_atom(field_name), do: field_ai_opts(nil, field_name)

  # The trait's options win; the app's `fields` config fills in what the trait
  # leaves out, so a site can pick a model for a field whose prompt a trait
  # provides.
  def field_ai_opts(schema, field_name) when is_atom(field_name) do
    trait = normalize_ai_opts(Brando.Trait.get_trait_ai_field_opts(schema, field_name))
    app = normalize_ai_opts(get_field_config(Keyword.get(config(), :fields, %{}), field_name))

    Keyword.merge(app, trait)
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

  @doc """
  The `"provider:model"` spec `ai_opts` resolve to, or `nil` when none is
  configured. `ai_opts[:model]` is a spec or a name in `models:`; a name that
  is not configured, and no `:model` at all, give the `:default` model.
  """
  @spec model_spec(keyword() | map()) :: String.t() | nil
  def model_spec(ai_opts \\ []) do
    case resolve_model(normalize_ai_opts(ai_opts)) do
      {:ok, spec} -> spec
      _ -> nil
    end
  end

  defp resolve_model(ai_opts) do
    case model_for(Keyword.get(ai_opts, :model)) do
      spec when is_binary(spec) and spec != "" -> {:ok, spec}
      _ -> {:error, :missing_model}
    end
  end

  defp model_for(spec) when is_binary(spec) and spec != "", do: spec
  defp model_for(name) when is_atom(name) and name not in [nil, :default], do: named_model(name) || default_model()
  defp model_for(_), do: default_model()

  defp named_model(name), do: config() |> Keyword.get(:models, []) |> Keyword.get(name)
  defp default_model, do: named_model(:default) || Keyword.get(config(), :default_model)

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
