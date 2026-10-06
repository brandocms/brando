defmodule Brando.SyncTest.ArticleListing do
  @moduledoc false
  # The `:user_context` listing's callbacks
  use Phoenix.Component

  import Ecto.Query

  def put_viewer(entries, user), do: Enum.map(entries, &Map.put(&1, :viewer, user.name))

  def row(assigns) do
    ~H"""
    <div class="user-context-row" data-viewer={@entry.viewer} data-user={@current_user.name}>{@entry.title}</div>
    """
  end

  def longest_title_first(query), do: from(q in query, order_by: [desc: fragment("length(?)", q.title), asc: q.id])

  def never(_user), do: false
  def named?(user), do: is_binary(user.name)
end
