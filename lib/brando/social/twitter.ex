defmodule Brando.Social.Twitter do
  @moduledoc """
  Tools for Twitter.
  """
  @doc """
  Creates a link to twitter's link sharer.

  ## Example

      share_url(@conn, "this is my description")

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

      <%= Brando.Social.Pinterest.link @conn, "Check out #{@product.name}") do %>
        This links to twitter!
      <% end %>

  """
  def link(conn, twitter_text, do: {:safe, link_contents}) do
    content_tag :a, link_contents, [href: share_url(conn, twitter_text), title: link_contents |> to_string]
  end
end