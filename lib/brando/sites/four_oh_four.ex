defmodule Brando.Sites.FourOhFour do
  def add_404(conn) do
    Cachex.incr(:four_oh_four, Path.join(["/" | conn.path_info]), 1)
    conn
  end

  def list() do
    :four_oh_four
    |> Cachex.stream!()
    |> Enum.map(fn {:entry, url, timestamp, _, hits} ->
      %{url: url, hits: hits, last_hit_at: timestamp}
    end)
    |> Enum.sort(&(&1.hits >= &2.hits))
  end
end
