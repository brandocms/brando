defmodule Brando.Mailer do
  @moduledoc """
  Sends Brando's email — a password reset, a form submission — through the
  application's own Swoosh mailer.

      config :brando, mailer: MyApp.Mailer

      config :brando, Brando.Mailer,
        from: {"My site", "noreply@example.com"},
        reply_to: "post@example.com"

  `mix brando.gen.mail` creates the mailer and sets `:mailer`. The sender is
  the address your mail provider lets you send from; `:reply_to` is optional.
  `:from` may be a plain address, which is then sent in the name of the
  site's identity.

  On a multi-site installation, a site can send as itself, by site key:

      config :brando, Brando.Mailer,
        from: {"Univers", "noreply@univers.no"},
        sites: %{
          "acme" => [from: {"Acme", "noreply@acme.no"}, reply_to: "post@acme.no"]
        }

  Build an email with `new/1`, give it a body in the shared layout with
  `Brando.Mailer.Layout.put_body/2`, and send it with `deliver_later/1`, which
  sends it from a background job and tries again if the provider fails. Use
  `deliver/1` only where the caller must know the email went out.

  Without a mailer, sending raises in development and test, so it is noticed.
  In production it logs a warning and returns `{:error, :no_mailer}`, and the
  caller carries on: a form submission is still stored.
  """

  require Logger

  alias Brando.Exception.ConfigError
  alias Swoosh.Email

  @doc """
  A new email from the current site's sender, with its reply-to address when
  one is set. `fields` are passed to `Swoosh.Email.new/1`, and override the
  sender.
  """
  @spec new(keyword()) :: Email.t()
  def new(fields \\ []) do
    sender = sender()

    defaults =
      [from: sender[:from], reply_to: sender[:reply_to]]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    Email.new(Keyword.merge(defaults, fields))
  end

  @doc """
  The current site's sender: `[from: {name, address}, reply_to: address]`,
  from the site's entry under `:sites`, else the general settings.
  `:from` is nil when no sender is configured.
  """
  @spec sender() :: [from: {String.t(), String.t()} | nil, reply_to: String.t() | nil]
  def sender do
    config = Application.get_env(:brando, __MODULE__, [])
    site = site_config(config)

    [
      from: (site[:from] || config[:from]) |> named(),
      reply_to: site[:reply_to] || config[:reply_to]
    ]
  end

  @doc "The application's Swoosh mailer, or nil when none is configured."
  @spec mailer() :: module() | nil
  def mailer, do: Application.get_env(:brando, :mailer)

  @doc "Whether a mailer is configured, so email can be sent."
  @spec configured?() :: boolean()
  def configured?, do: not is_nil(mailer())

  @doc """
  `:ok` when a mailer and an address to send from are configured. Otherwise
  the same as sending: raises in development and test, and in production logs
  a warning and returns `{:error, :no_mailer}` or `{:error, :no_sender}`.

  Use it before work that is pointless without email, such as creating a
  password reset link.
  """
  @spec ensure_configured() :: :ok | {:error, :no_mailer | :no_sender}
  def ensure_configured do
    with {:ok, _mailer} <- fetch_mailer(),
         {:ok, _email} <- put_sender(Email.new()) do
      :ok
    end
  end

  @doc """
  Sends `email` now, with the current site's sender when it has none.
  Returns what the mailer returns, or `{:error, :no_mailer}`.
  """
  @spec deliver(Email.t()) :: {:ok, term()} | {:error, term()}
  def deliver(%Email{} = email) do
    with {:ok, mailer} <- fetch_mailer(),
         {:ok, email} <- put_sender(email) do
      mailer.deliver(email)
    end
  end

  @doc """
  Sends `email` from a background job, which keeps the site it was sent from
  and tries again when the provider fails. Email sent outside any site, such
  as an account email from the login page, is queued without one. Returns
  `{:ok, job}`, or `{:error, :no_mailer}` without queueing anything.

  The job carries the addresses, subject, bodies and headers; attachments and
  provider options cannot be queued, so send those with `deliver/1`.
  """
  @spec deliver_later(Email.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def deliver_later(%Email{} = email) do
    with {:ok, _mailer} <- fetch_mailer(),
         {:ok, email} <- put_sender(email) do
      email
      |> Brando.Worker.Mail.args()
      |> Brando.Tenant.Job.attach_current()
      |> Brando.Worker.Mail.new()
      |> Oban.insert()
    end
  end

  defp fetch_mailer do
    case mailer() do
      nil ->
        missing!(
          :no_mailer,
          "No mailer is configured for Brando, so it cannot send email. Set the application's Swoosh mailer:\n\n" <>
            "    config :brando, mailer: MyApp.Mailer\n\n`mix brando.gen.mail` creates one."
        )

      mailer ->
        {:ok, mailer}
    end
  end

  defp put_sender(%Email{from: from} = email) when from not in [nil, {"", ""}], do: {:ok, email}

  defp put_sender(email) do
    case sender() do
      [from: nil, reply_to: _] ->
        missing!(
          :no_sender,
          "Brando has no address to send email from. Set it to an address your mail provider sends for:\n\n" <>
            "    config :brando, Brando.Mailer, from: {\"My site\", \"noreply@example.com\"}"
        )

      [from: from, reply_to: reply_to] ->
        email = Email.from(email, from)
        {:ok, if(is_nil(email.reply_to) and reply_to, do: Email.reply_to(email, reply_to), else: email)}
    end
  end

  # Raised where a developer sees it; logged in production, where the caller
  # decides what to do without the email.
  defp missing!(reason, message) do
    if Brando.env() in [:dev, :test, :e2e] do
      raise ConfigError, message: message
    else
      Logger.warning("[Brando.Mailer] " <> message)
      {:error, reason}
    end
  end

  defp site_config(config) do
    case {config[:sites], Brando.Tenant.current_site_key()} do
      {sites, key} when is_map(sites) and is_binary(key) -> Map.get(sites, key, [])
      _ -> []
    end
  end

  defp named(nil), do: nil
  defp named({_name, _address} = from), do: from
  defp named(address) when is_binary(address), do: {site_name(), address}

  defp site_name do
    language = to_string(Brando.config(:default_language) || "en")

    case Brando.Cache.Identity.get(language) do
      %{name: name} when is_binary(name) -> name
      _ -> ""
    end
  end
end
