defmodule Brando.Plug.Lockdown do
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

  @doc "Whether `given` is the configured `lockdown_password`."
  @spec password?(term()) :: boolean()
  def password?(given) do
    case password() do
      nil -> false
      password -> is_binary(given) and Plug.Crypto.secure_compare(given, password)
    end
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

      password?(key(conn)) ->
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
