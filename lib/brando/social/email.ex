defmodule Brando.Social.Email do
  @moduledoc """
  Tools for Email.
  """
  import Phoenix.HTML.Tag, only: [content_tag: 3]

  defp share_url(conn, subject) do
    url = Brando.Utils.current_url(conn)
    ~s(mailto:?subject=#{subject}&body=#{url})
  end

  @doc ~S"""
  Create a twitter link.

  ## Example

      <%= Brando.Social.Email.link @conn, "This is the subject") do %>
        This links to an email!
      <% end %>

  """
  def link(conn, subject, do: {:safe, link_contents}) do
    content_tag(:a, link_contents, href: share_url(conn, subject), title: to_string(link_contents))
  end
end
