defmodule Brando.Forms.Turnstile do
  @moduledoc """
  Cloudflare Turnstile, the spam check on form submissions.

      config :brando, Brando.Forms,
        turnstile: [
          site_key: System.get_env("TURNSTILE_SITE_KEY"),
          secret_key: System.get_env("TURNSTILE_SECRET_KEY")
        ]

  With both keys set, `Brando.HTML.Forms.site_form/1` renders the widget and
  every submission must carry a token Cloudflare confirms. Without them, forms
  rely on the honeypot field and rate limiting alone.

  Cloudflare's test keys (`1x00000000000000000000AA` with
  `1x0000000000000000000000000000000AA`) always pass. `req_options` are merged
  into the verification request, e.g. `[plug: {Req.Test, Brando.Forms.Turnstile}]`
  in tests.
  """

  require Logger

  @verify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  @doc "The site key the widget renders with, or nil when Turnstile is not configured."
  def site_key, do: if(enabled?(), do: config()[:site_key])

  @doc "Whether both keys are configured."
  def enabled?, do: present?(config()[:site_key]) and present?(config()[:secret_key])

  @doc """
  Confirms the widget's token with Cloudflare. Returns `:ok` when Turnstile is
  not configured.
  """
  @spec verify(String.t() | nil, String.t() | nil) :: :ok | {:error, term()}
  def verify(token, remote_ip) do
    cond do
      not enabled?() -> :ok
      not present?(token) -> {:error, :missing_token}
      true -> request(token, remote_ip)
    end
  end

  defp request(token, remote_ip) do
    form = Enum.reject([secret: config()[:secret_key], response: token, remoteip: remote_ip], &is_nil(elem(&1, 1)))

    [url: @verify_url, form: form, receive_timeout: 10_000, retry: false]
    |> Keyword.merge(config()[:req_options] || [])
    |> Req.post()
    |> case do
      {:ok, %{status: 200, body: %{"success" => true}}} ->
        :ok

      {:ok, %{body: body}} ->
        {:error, {:rejected, error_codes(body)}}

      {:error, reason} ->
        # Cloudflare unreachable: refuse rather than let unchecked posts through.
        Logger.warning("Turnstile verification failed: #{inspect(reason)}")
        {:error, :unavailable}
    end
  end

  defp error_codes(%{"error-codes" => codes}), do: codes
  defp error_codes(_), do: []

  defp config do
    :brando |> Application.get_env(Brando.Forms, []) |> Keyword.get(:turnstile, [])
  end

  defp present?(value), do: is_binary(value) and value != ""
end
