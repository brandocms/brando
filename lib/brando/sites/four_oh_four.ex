defmodule Brando.Sites.FourOhFour do
  def add_404(conn) do
    Cachex.incr(:four_oh_four, Path.join(["/" | conn.path_info]), 1)
    conn
  end

  def list() do
    :four_oh_four
    |> Cachex.stream!()
    |> Enum.map(fn {:entry, url, hits, timestamp, _} ->
      last_hit_at =
        timestamp
        |> DateTime.from_unix!(:millisecond)
        |> Brando.Utils.Datetime.format_datetime("%d/%m/%y, %H:%M")

      %{url: url, hits: hits, last_hit_at: last_hit_at}
    end)
    |> Enum.sort(&(&1.hits >= &2.hits))
  end
end
