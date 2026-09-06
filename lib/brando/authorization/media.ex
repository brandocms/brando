defmodule Brando.Authorization.Media do
  @moduledoc "Authorization and captured scope for media transfers."
  alias Brando.Authorization.{Boundary, Engine, Scope}

  @salt "brando-authorized-upload-scope"
  def token(user) do
    if Engine.enabled?(), do: Phoenix.Token.sign(Brando.endpoint(), @salt, Scope.current(user))
  end

  def with_intent(target, user, fun) do
    if Engine.enabled?() do
      with {:ok, %Scope{user_id: id} = scope} <-
             Phoenix.Token.verify(Brando.endpoint(), @salt, target["scope_token"], max_age: 86_400),
           true <- is_map(user) and id == Map.get(user, :id),
           :ok <- Engine.authorize(scope, :access, :backend) do
        Boundary.with_scope(scope, fn -> Brando.Tenant.with_prefix(scope.prefix, fun) end)
      else
        _ -> {:error, "Your upload access has changed. Reload the page and try again."}
      end
    else
      fun.()
    end
  end

  def authorize(actor, type, action \\ :create) do
    schema =
      case type do
        :image -> Brando.Images.Image
        :file -> Brando.Files.File
        :video -> Brando.Videos.Video
        _ -> nil
      end

    case Boundary.authorize(actor, action, schema) do
      :ok -> :ok
      _ -> {:error, "You do not have permission to #{action} this media."}
    end
  end

  def authorize_config(actor, %{__struct__: module}) do
    type =
      case module do
        Brando.Type.ImageConfig -> :image
        Brando.Type.FileConfig -> :file
        Brando.Type.VideoConfig -> :video
        _ -> nil
      end

    authorize(actor, type)
  end
end
