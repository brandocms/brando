defmodule Brando.Social.Pinterest do
  @moduledoc """
  Tools for Pinterest.
  """
  @doc ~S"""
  Creates a link to pinterest's link sharer.

  ## Example

      share_url(@conn, img(@product.photo, :xlarge, [prefix: media_url()]),
                "#{@product.collection.name}")

  """
  def share_url(conn, media, text) do
    url = Brando.Utils.escape_current_url(conn)
    media = Brando.Utils.escape_and_prefix_host(conn, media)
    text = URI.encode_www_form(text)
    ~s(https://pinterest.com/pin/create/button/?url=#{url}&media=#{media}&description=#{text}")
  end
end