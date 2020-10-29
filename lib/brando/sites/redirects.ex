defmodule Brando.Sites.Redirects do
  def match_redirect(test_url, from, to) do
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
        test_url

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
