defmodule Brando.Plug.MediaSlowdowner do
  @moduledoc """
  Plug for slowing down media image queries.

  Should only be used for testing frontend lazyload stuff

  ## Usage

  Add the plug to your endpoint.ex:

      plug Brando.Plug.MediaSlowdowner, path: ["media", "images"], duration: 5000

  """

  # import Plug.Conn
  @behaviour Plug

  def init(opts) do
    path = Keyword.get(opts, :path, ["media", "images"])
    duration = Keyword.get(opts, :duration, 5000)
    %{path: path, duration: duration}
  end

  def call(%Plug.Conn{path_info: path_info} = conn, %{path: path, duration: duration}) do
    if match_path?(path_info, path) do
      require Logger

      Logger.error("""
      == Slowing down request by #{duration} ms
      >> Path: #{Path.join(path_info)}
      """)

      :timer.sleep(duration)
    end

    conn
  end

  # Helper function to match paths
  defp match_path?(conn_path, path_to_match) do
    Enum.take(conn_path, length(path_to_match)) == path_to_match
  end
end
