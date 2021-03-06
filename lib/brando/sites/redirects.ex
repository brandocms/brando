defmodule Brando.Sites.Redirects do
  @doc """
  Check `test_path` against registered redirects
  """
  @spec test_redirect(list) ::
          {:ok, {:redirect, {binary, binary}}} | {:error, {:redirects, :no_match}}
  def test_redirect(test_path) do
    test_url = "/" <> Enum.join(test_path, "/")
    seo = Brando.Cache.SEO.get()

    Enum.reduce_while(seo.redirects, {:error, {:redirects, :no_match}}, fn redirect, _acc ->
      case match_redirect(test_url, redirect.from, redirect.to) do
        {:error, _} ->
          {:cont, {:error, {:redirects, :no_match}}}

        url ->
          {:halt, {:ok, {:redirect, {url, redirect.code}}}}
      end
    end)
  end

  defp match_redirect(test_url, from, to) do
    from_regex =
      from
      |> String.split("/")
      |> Enum.map_join("/", fn
        ":" <> segment ->
          "(?<#{segment}>[a-z0-9\-\_]+)"

        segment ->
          segment
      end)
      |> Regex.compile!()

    case Regex.named_captures(from_regex, test_url) do
      nil ->
        {:error, {:redirects, :no_match}}

      captured_segments ->
        to
        |> String.split("/")
        |> Enum.map_join("/", fn
          ":" <> segment ->
            Map.get(captured_segments, segment, ":#{segment}")

          segment ->
            segment
        end)
    end
  end
end
