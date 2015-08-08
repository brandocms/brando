defmodule Brando.Social.Facebook do
  @moduledoc """
  Tools for Facebook.
  """
  @doc """
  Creates a link to facebook's link sharer.

  You need to have your page's META in order for this to work properly.

  ## Example

      share_url(@conn)

  """
  import Phoenix.HTML.Tag, only: [content_tag: 3]

  defp share_url(conn) do
    url = Brando.Utils.escape_current_url(conn)
    ~s(https://www.facebook.com/sharer/sharer.php?u=#{url})
  end

  @doc ~S"""
  Create a facebook link.

  ## Example

      <%= Brando.Social.Pinterest.link @conn do %>
        This links to facebook!
      <% end %>

  """
  def link(conn, do: {:safe, link_contents}) do
    content_tag :a, link_contents, [href: share_url(conn), title: link_contents |> to_string]
  end
end