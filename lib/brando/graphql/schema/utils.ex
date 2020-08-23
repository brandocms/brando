defmodule Brando.Schema.Utils do
  @moduledoc """
  Helper utility functions for GraphQL resolvers
  """
  def resolve_avatar(%{avatar: nil}, _, _) do
    {:ok, "/images/admin/avatar.png"}
  end

  def resolve_avatar(user, %{type: type}, _) do
    img_url = Brando.Utils.img_url(user.avatar, type, prefix: Brando.Utils.media_url())
    {:ok, img_url}
  end
end
