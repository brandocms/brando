defmodule Brando.Sites.FourOhFour do
  @moduledoc false
  def add_404(conn) do
    key = Path.join(["/" | conn.path_info]) |> Brando.Tenant.cache_key()
    Cachex.incr(:four_oh_four, key, 1)
    conn
  end

  @doc "Forgets a recorded URL, e.g. once a redirect covers it."
  def remove(url) when is_binary(url) do
    Cachex.del(:four_oh_four, Brando.Tenant.cache_key(url))
    :ok
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

  # Requests no real visitor or broken link makes: scanners looking for
  # WordPress, PHP shells, exposed config and credentials. They're kept, but
  # the SEO view folds them away so the 404s worth a redirect stand out.
  @probe_patterns [
    # PHP scripts and their editor/backup copies: x.php, x.php~, x.php.bak
    ~r/\.php\d?(?:[.~]|$)/i,
    # Dotfiles and dot-directories (.env, .git/, .ssh/, .aws/, .htaccess),
    # except .well-known/, which real services use
    ~r{(?:^|/)\.(?!well-known/)[^/]},
    ~r{(?:^|/)wp-|wordpress}i,
    ~r{phpunit|eval-stdin|/vendor/|^/cgi-bin/|^/containers/json$}i,
    ~r{(?:^|/)(?:config|secrets|credentials)\.(?:json|ya?ml|php|ini)$}i
  ]

  @doc """
  Whether a 404'd path looks like a vulnerability scanner's probe rather than
  a moved page or a broken link.
  """
  @spec probe?(String.t()) :: boolean()
  def probe?(url) when is_binary(url) do
    path = url |> URI.parse() |> Map.get(:path) |> Kernel.||("") |> URI.decode()
    Enum.any?(@probe_patterns, &Regex.match?(&1, path))
  end

  defp matches_prefix?({:tenant, prefix, _key}, prefix), do: true
  defp matches_prefix?(key, nil) when not is_tuple(key), do: true
  defp matches_prefix?(_key, _prefix), do: false

  defp unwrap_key({:tenant, _prefix, key}), do: key
  defp unwrap_key(key), do: key
end
