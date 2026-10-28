defmodule Brando.LivePreview.SocketToken do
  @moduledoc """
  The token a live-preview document connects to its socket with.

  The preview document holds the site's own markup, editor content included,
  sandboxed in an opaque origin. It gets this token instead of the viewer's
  admin socket token (`Brando.Users.build_socket_token/2`): signed with its own
  salt, it names the viewer, their session and one preview key, with the
  site and environment the preview was registered in, and lasts 15 minutes.
  `BrandoAdmin.LivePreviewSocket`, which the endpoint mounts at
  `/__livepreview/socket`, connects it, and joins only `live_preview:<key>`
  for that key; `BrandoAdmin.AdminSocket` refuses it. `BrandoAdmin.LivePreviewChannel` hands the
  preview a fresh one before it expires, for its next connect.
  """
  alias Brando.Repo
  alias Brando.Users
  alias Brando.Users.UserToken

  @salt "brando_live_preview_socket"
  @max_age 15 * 60

  @doc "How long a token lasts, in seconds."
  def max_age, do: @max_age

  @doc """
  A token for `user`'s session with the token row id `session_id`, good only
  for the live preview `key`.
  """
  @spec build(%{id: integer()}, integer(), String.t(), keyword()) :: String.t()
  def build(%{id: user_id}, session_id, key, opts \\ []) when is_integer(session_id) and is_binary(key) do
    claims = %{
      "user_id" => user_id,
      "session_id" => session_id,
      "key" => key,
      "tenant" => tenant(key)
    }

    Phoenix.Token.sign(Brando.endpoint(), @salt, claims, Keyword.take(opts, [:signed_at]))
  end

  @doc """
  The viewer, session and preview behind a token from `build/4`, while the
  token is fresh and the session lasts: `{:ok, %{user_id: id, session_id: id,
  socket_id: id, key: key, tenant: tenant}}`, or `{:error, :invalid}`.
  `socket_id` is the session's `Brando.Users.live_socket_id/1`, so ending the
  session disconnects the preview's socket as well.
  """
  @spec verify(String.t() | nil) :: {:ok, map()} | {:error, :invalid}
  def verify(token) when is_binary(token) do
    with {:ok, %{"user_id" => user_id, "session_id" => session_id, "key" => key} = claims}
         when is_integer(user_id) and is_integer(session_id) and is_binary(key) <-
           Phoenix.Token.verify(Brando.endpoint(), @salt, token, max_age: @max_age),
         session_token when is_binary(session_token) <-
           Repo.one(UserToken.verify_session_id_query(session_id, user_id)) do
      {:ok,
       %{
         user_id: user_id,
         session_id: session_id,
         socket_id: Users.live_socket_id(session_token),
         key: key,
         tenant: claims["tenant"]
       }}
    else
      _ -> {:error, :invalid}
    end
  end

  def verify(_token), do: {:error, :invalid}

  @doc """
  The site and environment `key` was registered in, as the token records it:
  `[site_id, environment_id]`, or nil for a preview outside a site workspace.
  """
  @spec tenant(String.t()) :: [integer() | nil] | nil
  def tenant(key) do
    case Brando.Authorization.Preview.scope(key) do
      %{site_id: site_id, environment_id: environment_id} when not is_nil(site_id) -> [site_id, environment_id]
      _ -> nil
    end
  end
end
