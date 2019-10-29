defmodule Brando.Social.Pinterest do
  @moduledoc """
  Tools for Pinterest.
  """
  import Phoenix.HTML.Tag, only: [content_tag: 3]

  defp share_url(conn, media, text) do
    url = Brando.Utils.escape_current_url(conn)
    media = Brando.Utils.escape_and_prefix_host(conn, media)
    text = URI.encode_www_form(text)

    ~s(https://pinterest.com/pin/create/button/?url=) <>
      ~s(#{url}&media=#{media}&description=#{text}")
  end

  @doc ~S"""
  Create a pinterest link.

  ## Example

      <%= Brando.Social.Pinterest.link @conn,
          img_url(@p.photo, :xlarge, [prefix: media_url()]), "#{@p.name}") do %>
        my link text here
      <% end %>

  """
  def link(conn, media, pinterest_text, do: {:safe, link_contents}) do
    content_tag(:a, link_contents,
      href: share_url(conn, media, pinterest_text),
      title: to_string(link_contents)
    )
  end
end
