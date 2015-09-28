defmodule Brando.Social.Twitter do
  @moduledoc """
  Tools for Twitter.
  """
  import Phoenix.HTML.Tag, only: [content_tag: 3]

  defp share_url(conn, text) do
    url = Brando.Utils.escape_current_url(conn)
    text = URI.encode_www_form(text)
    ~s(https://twitter.com/intent/tweet?url=#{url}&text=#{text})
  end

  @doc ~S"""
  Create a twitter link.

  ## Example

      <%= Brando.Social.Pinterest.link @conn, "#{@product.name}") do %>
        This links to twitter!
      <% end %>

  """
  def link(conn, twitter_text, do: {:safe, link_contents}) do
    content_tag :a, link_contents,
      [href: share_url(conn, twitter_text), title: to_string(link_contents)]
  end
end
