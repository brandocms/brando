defmodule Brando.AI.Cassette.Redact do
  @moduledoc """
  Keeps secrets out of cassette files.

  Before a cassette is written:

    * values under keys that name credentials (`api_key`, `authorization`,
      `x-api-key`, `access_token`, `secret`, `password` and the like) become
      `"[REDACTED]"`;
    * every API key Brando knows — the request's own `:api_key`, the keys in
      `Brando.AI`'s provider configuration and the usual provider environment
      variables — is replaced wherever it appears in text;
    * strings shaped like provider keys or bearer tokens are replaced too.

  The normalised request never carries the key or HTTP options in the first
  place; this is the second line.
  """

  @redacted "[REDACTED]"

  @secret_keys ~w(api_key apikey api-key x-api-key x-goog-api-key anthropic-api-key authorization
                  proxy-authorization access_token refresh_token id_token secret client_secret
                  password bearer cookie set-cookie)

  @env_keys ~w(ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY GEMINI_API_KEY OPENROUTER_API_KEY
               GROQ_API_KEY MISTRAL_API_KEY XAI_API_KEY)

  @patterns [
    ~r/\bsk-[A-Za-z0-9_\-]{16,}/,
    ~r/\bAIza[0-9A-Za-z_\-]{30,}/,
    ~r/\b[Bb]earer\s+[A-Za-z0-9._~+\/=\-]{12,}/
  ]

  @doc "Redact `term`, also replacing each of `secrets` wherever it appears."
  @spec redact(term(), [String.t()]) :: term()
  def redact(term, secrets \\ []) do
    secrets =
      (secrets ++ known_secrets())
      |> Enum.filter(&(is_binary(&1) and byte_size(&1) >= 8))
      |> Enum.uniq()
      |> Enum.sort_by(&(-byte_size(&1)))

    walk(term, secrets)
  end

  defp walk(map, secrets) when is_map(map) do
    Map.new(map, fn {key, value} ->
      if secret_key?(key), do: {key, @redacted}, else: {key, walk(value, secrets)}
    end)
  end

  defp walk(list, secrets) when is_list(list), do: Enum.map(list, &walk(&1, secrets))
  defp walk(text, secrets) when is_binary(text), do: scrub(text, secrets)
  defp walk(other, _secrets), do: other

  defp secret_key?(key), do: key |> to_string() |> String.downcase() |> then(&(&1 in @secret_keys))

  defp scrub(text, secrets) do
    text = Enum.reduce(secrets, text, &String.replace(&2, &1, @redacted))
    Enum.reduce(@patterns, text, &Regex.replace(&1, &2, @redacted))
  end

  @doc "The API keys in the app's configuration and environment."
  @spec known_secrets() :: [String.t()]
  def known_secrets do
    config = Application.get_env(:brando, Brando.AI, [])

    provider_keys =
      config
      |> Keyword.get(:providers, [])
      |> Enum.map(fn {_provider, opts} -> provider_key(opts) end)

    agent_key = Keyword.get(Application.get_env(:brando, Brando.AI.Agent, []), :api_key)
    app_keys = for {key, value} <- config, key |> to_string() |> String.ends_with?("_api_key"), do: value

    [agent_key | provider_keys ++ app_keys ++ Enum.map(@env_keys, &System.get_env/1)]
    |> Enum.filter(&is_binary/1)
  end

  defp provider_key(opts) when is_list(opts), do: Keyword.get(opts, :api_key)
  defp provider_key(%{} = opts), do: Map.get(opts, :api_key) || Map.get(opts, "api_key")
  defp provider_key(_), do: nil
end
