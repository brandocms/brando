defmodule Brando.Sites.FourOhFour do
  @moduledoc false
  def add_404(conn) do
    key = Path.join(["/" | conn.path_info]) |> Brando.Tenant.cache_key()
    Cachex.incr(:four_oh_four, key, 1)
    conn
  end

  def list do
    current_prefix = Brando.Tenant.current_prefix()

    :four_oh_four
    |> Cachex.stream!()
    |> Enum.filter(fn {:entry, key, _hits, _timestamp, _} ->
      matches_prefix?(key, current_prefix)
    end)
    |> Enum.map(fn {:entry, key, hits, timestamp, _} ->
      last_hit_at =
        timestamp
        |> DateTime.from_unix!(:millisecond)
        |> Brando.Utils.Datetime.format_datetime("%d/%m/%y, %H:%M")

      %{url: unwrap_key(key), hits: hits, last_hit_at: last_hit_at}
    end)
    |> Enum.sort(&(&1.hits >= &2.hits))
  end

  defp matches_prefix?({:tenant, prefix, _key}, prefix), do: true
  defp matches_prefix?(key, nil) when not is_tuple(key), do: true
  defp matches_prefix?(_key, _prefix), do: false

  defp unwrap_key({:tenant, _prefix, key}), do: key
  defp unwrap_key(key), do: key
end
