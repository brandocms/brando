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
  def share_url(conn) do
    url = Brando.Utils.escape_current_url(conn)

    ~s(https://www.facebook.com/sharer/sharer.php?u=#{url})
  end
end