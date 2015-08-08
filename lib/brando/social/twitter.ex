defmodule Brando.Social.Twitter do
  @moduledoc """
  Tools for Twitter.
  """
  @doc """
  Creates a link to twitter's link sharer.

  ## Example

      share_url(@conn, "this is my description")

  """
  def share_url(conn, text) do
    url = Brando.Utils.escape_current_url(conn)
    text = URI.encode_www_form(text)
    ~s(https://twitter.com/intent/tweet?url=#{url}&text=#{text})
  end
end