defmodule BrandoAdmin.FigmaCallbackController do
  @moduledoc """
  Where Figma sends the browser back after consent, at the redirect URL
  `Brando.Figma.OAuth.redirect_url/0` shows: finishes the connection its
  `state` started (`Brando.Figma.OAuth.finish/3`), for the signed-in person
  and session that started it, and goes back to the settings page with the
  outcome (`?figma=…`), in the site environment the connection was made for.
  """
  use BrandoAdmin, :controller

  alias Brando.Figma.OAuth

  require Logger

  @callback_suffix "/figma/callback"

  def show(conn, _params) do
    {outcome, tenant} = finish(conn)

    conn
    |> put_environment(tenant)
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> redirect(to: settings_path(conn) <> "?" <> URI.encode_query(%{"figma" => outcome}))
  end

  # A failure is "could not save, try again", logged without the request,
  # whose query carries Figma's code and the state
  defp finish(conn) do
    # The query only: an endpoint without Plug.Parsers has no other params
    params = fetch_query_params(conn).query_params
    session_id = Brando.Users.token_id(get_session(conn, :user_token))

    case OAuth.finish(params, conn.assigns.current_user, session_id) do
      {:ok, tenant} -> {"connected", tenant}
      {:error, reason, tenant} -> {to_string(reason), tenant}
    end
  rescue
    error ->
      Logger.error(
        "[BrandoAdmin.FigmaCallbackController] Finishing a Figma connection raised #{inspect(error.__struct__)}"
      )

      {"save_failed", nil}
  catch
    kind, _reason ->
      Logger.error("[BrandoAdmin.FigmaCallbackController] Finishing a Figma connection failed (#{kind})")
      {"save_failed", nil}
  end

  # Back in the site environment the connection was made for, should the
  # session have moved to another one meanwhile
  defp put_environment(conn, %{site: %{key: site_key}, environment: %{key: environment_key}}) do
    conn
    |> put_session("brando_site_key", site_key)
    |> put_session("brando_environment_key", environment_key)
  end

  defp put_environment(conn, _tenant), do: conn

  # The settings page under the same mount path as this callback
  defp settings_path(conn), do: String.replace_suffix(conn.request_path, @callback_suffix, "")
end
