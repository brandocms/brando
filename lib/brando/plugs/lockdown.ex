defmodule Brando.Plug.Lockdown do
  @attempts_per_window 10
  @attempt_window :timer.minutes(15)

  @moduledoc """
  Basic plug for locking down websites under development

  While locked, visitors are redirected to `lockdown_path(conn, :index)`,
  which `mix brando.gen.site` routes to `YourWeb.CMS.LockdownController` at
  `/coming-soon`. Users with access to the admin, the admin's live preview,
  shared preview links (`/__p__/…`) and visitors who have entered the
  password are let through.

  ## Example

  ```elixir
      plug Brando.Plug.Lockdown
  ```

  The plug needs the session fetched, so it goes in a pipeline after
  `:browser`. `mix brando.gen.site` puts it in the `:brando_site` pipeline.

  ## Configure

      config :brando,
        lockdown: true,
        lockdown_password: "my_pass",
        lockdown_until: ~U[2040-01-13 13:00:00Z]

  `lockdown_password` and `lockdown_until` are optional. Without a password
  (or with an empty one), only users with access to the admin see the site.
  Past `lockdown_until`, the site is open.

  You can also add the password as a query string to set a cookie that allows browsing.

  `https://website/?key=<pass>`

  Wrong password attempts are limited to #{@attempts_per_window} per client address in
  #{div(@attempt_window, 60_000)} minutes (`password?/2`, which the lockdown
  page's controller calls), so the password cannot be guessed by trying
  many. The address is the client's, also behind a trusted reverse proxy
  (`Brando.ClientIP`).
  """
  @behaviour Plug

  import Phoenix.Controller, only: [redirect: 2]
  import Plug.Conn, only: [halt: 1]

  alias Brando.Authorization.Engine
  alias Brando.Users

  def init(options), do: options

  def call(conn, _) do
    if Brando.config(:lockdown) do
      allowed?(conn)
    else
      conn
    end
  end

  @doc """
  The configured `lockdown_password`, or nil when there is none: an unset or
  empty password lets no visitor in by password.
  """
  @spec password() :: String.t() | nil
  def password do
    case Brando.config(:lockdown_password) do
      password when is_binary(password) and password != "" -> password
      _ -> nil
    end
  end

  @doc """
  Whether `given` is the configured `lockdown_password`, with no limit on
  attempts. Use `password?/2` for what a visitor sent.
  """
  @deprecated "Use password?/2, which limits a visitor's attempts"
  @spec password?(term()) :: boolean()
  def password?(given) do
    case password() do
      nil -> false
      password -> is_binary(given) and Plug.Crypto.secure_compare(given, password)
    end
  end

  @doc """
  Whether `given`, sent by the visitor at `conn`, is the configured
  `lockdown_password`. A wrong one counts against the visitor's address (an
  IPv6 one by its /64); after #{@attempts_per_window} in #{div(@attempt_window, 60_000)} minutes, even
  the right password is refused there until the window ends. The right
  password costs nothing, so people sharing an address and a key link are
  not locked out.
  """
  @spec password?(Plug.Conn.t(), term()) :: boolean()
  def password?(%Plug.Conn{} = conn, given) do
    bucket = {__MODULE__, conn |> Brando.ClientIP.from_conn() |> Brando.ClientIP.rate_key()}

    cond do
      password() == nil -> false
      Brando.RateLimit.count(bucket, @attempt_window) >= @attempts_per_window -> false
      password?(given) -> true
      true -> failed(bucket)
    end
  end

  defp failed(bucket) do
    _ = Brando.RateLimit.hit(bucket, @attempts_per_window, @attempt_window)
    false
  end

  defp allowed?(%{private: %{brando_live_preview: true}} = conn), do: conn

  # Shared preview links are for people without an admin account; the key in
  # the link is what grants access.
  defp allowed?(%{path_info: ["__p__", _preview_key]} = conn), do: conn

  defp allowed?(conn) do
    session = conn.private[:plug_session] || %{}

    cond do
      admin?(session["user_token"]) ->
        conn

      session["lockdown_authorized"] == true ->
        conn

      key(conn) != nil and password?(conn, key(conn)) ->
        Plug.Conn.put_session(conn, :lockdown_authorized, true)

      true ->
        lockdown(conn)
    end
  end

  defp key(%{query_params: %{"key" => key}}), do: key
  defp key(_conn), do: nil

  # The session the admin's sign-in writes (BrandoAdmin.UserAuth): whoever
  # can open /admin sees the locked site. In legacy mode that is any active
  # signed-in user; with groups, an account with backend access.
  defp admin?(token) when is_binary(token) do
    case Users.get_user_by_session_token(token) do
      nil -> false
      user -> not Engine.enabled?() or Engine.backend_access?(user)
    end
  end

  defp admin?(_token), do: false
  defp lockdown(conn), do: check_lockdown_date(conn, Brando.config(:lockdown_until))

  defp check_lockdown_date(conn, nil) do
    conn
    |> redirect(to: Brando.helpers().lockdown_path(conn, :index))
    |> halt()
  end

  defp check_lockdown_date(conn, lockdown_until) do
    if DateTime.after?(lockdown_until, DateTime.utc_now()) do
      conn
      |> redirect(to: Brando.helpers().lockdown_path(conn, :index))
      |> halt()
    else
      conn
    end
  end
end
