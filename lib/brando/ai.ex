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

  def generate_text(prompt, ai_opts \\ []) when is_binary(prompt) do
    ai_opts = normalize_ai_opts(ai_opts)

    with true <- enabled?(),
         {:ok, model} <- resolve_model(ai_opts),
         {:ok, provider} <- provider_from_model(model),
         {:ok, api_key} <- resolve_api_key(provider, ai_opts),
         req_opts <- build_req_opts(ai_opts, api_key),
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
