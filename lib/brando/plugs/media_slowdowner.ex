defmodule Brando.Plug.MediaSlowdowner do
  @moduledoc """
  Plug for slowing down media image queries.

  Should only be used for testing frontend lazyload stuff
  """

  # import Plug.Conn
  @behaviour Plug

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["media", "images" | _suffix] = path_info} = conn, opts) do
    duration = Keyword.get(opts, :duration, 5000)
    require Logger

    Logger.error("""

    == slowing down request for image by #{duration} ms
    >> path: #{Path.join(path_info)}

    """)

    :timer.sleep(duration)

    conn
  end

  def call(conn, _), do: conn
end
