defmodule Brando.SSG.PreviewRewrite do
  @moduledoc """
  Keeps a build's preview inside the build (`Brando.SSG.PreviewController`).

  A build's pages name the site's root: `/assets/app.css`, `/media/…`,
  `/about`, and absolute URLs on the site's host. Served under
  `/__ssg_preview__/:token/`, those would load the assets the host serves
  now and leave the preview for the live site. The preview rewrites them, in
  each HTML and CSS response, to the same path under the preview: in the
  `href`, `src`, `action`, `formaction`, `poster`, `data-src`, `srcset` and
  `data-srcset` attributes, and in CSS `url()`. The artifact's files are not
  changed. A `srcset` is read as a browser reads it, its character
  references decoded, so a `data:` candidate stays whole. URLs a script builds as it runs are not rewritten.
  """

  @url_attribute ~r/(\s(?:href|src|action|formaction|poster|data-src)\s*=\s*)(["'])([^"']*)\2/i
  @srcset_attribute ~r/(\s(?:srcset|data-srcset)\s*=\s*)(["'])([^"']*)\2/i
  @css_url ~r/url\(\s*(["']?)([^"')\s]+)\1\s*\)/i

  @doc """
  `html` with the site's root-relative URLs, and absolute URLs on one of
  `site_bases` (`"https://example.com"`), under `prefix`
  (`"/__ssg_preview__/token"`).
  """
  @spec html(String.t(), String.t(), [String.t()]) :: String.t()
  def html(html, prefix, site_bases) do
    html
    |> then(
      &Regex.replace(@url_attribute, &1, fn _all, name, quote, url ->
        name <> quote <> rewrite(url, prefix, site_bases) <> quote
      end)
    )
    |> then(
      &Regex.replace(@srcset_attribute, &1, fn _all, name, quote, srcset ->
        name <> quote <> rewrite_srcset(srcset, prefix, site_bases) <> quote
      end)
    )
    |> css(prefix, site_bases)
  end

  @doc "`css` with its `url()`s rewritten as `html/3` rewrites URLs."
  @spec css(String.t(), String.t(), [String.t()]) :: String.t()
  def css(css, prefix, site_bases) do
    Regex.replace(@css_url, css, fn _all, quote, url ->
      "url(" <> quote <> rewrite(url, prefix, site_bases) <> quote <> ")"
    end)
  end

  # As browsers read a srcset: a candidate's URL runs to the next whitespace,
  # commas included (a `data:` URL has one), less the commas it ends with;
  # its descriptors run to the next comma
  defp rewrite_srcset(srcset, prefix, site_bases) do
    srcset
    |> decode_attribute()
    |> srcset_candidates(prefix, site_bases, [])
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  # The value a browser reads from the attribute, its character references
  # decoded (`&#32;` is a space that separates candidates)
  defp decode_attribute(value) do
    case Floki.parse_fragment(~s(<img a=") <> value <> ~s(">)) do
      {:ok, [{"img", [{"a", decoded}], []}]} -> decoded
      _other -> value
    end
  end

  defp srcset_candidates("", _prefix, _site_bases, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp srcset_candidates(srcset, prefix, site_bases, acc) do
    [separator, rest] = Regex.run(~r/\A([\s,]*)(.*)\z/s, srcset, capture: :all_but_first)
    [url, rest] = Regex.run(~r/\A(\S*)(.*)\z/s, rest, capture: :all_but_first)
    [url, trailing_commas] = Regex.run(~r/\A(.*?)(,*)\z/s, url, capture: :all_but_first)

    {descriptors, rest} =
      if trailing_commas == "",
        do: ~r/\A([^,]*)(.*)\z/s |> Regex.run(rest, capture: :all_but_first) |> List.to_tuple(),
        else: {trailing_commas, rest}

    acc = [descriptors, rewrite_candidate(url, prefix, site_bases), separator | acc]
    srcset_candidates(rest, prefix, site_bases, acc)
  end

  defp rewrite_candidate("data:" <> _ = url, _prefix, _site_bases), do: url
  defp rewrite_candidate(url, prefix, site_bases), do: rewrite(url, prefix, site_bases)

  defp rewrite(url, prefix, site_bases) do
    cond do
      String.starts_with?(url, "//") -> url
      String.starts_with?(url, prefix <> "/") or url == prefix -> url
      String.starts_with?(url, "/") -> prefix <> url
      base = Enum.find(site_bases, &on_base?(url, &1)) -> prefix <> on_root(String.replace_prefix(url, base, ""))
      true -> url
    end
  end

  defp on_base?(url, base) do
    url == base or Enum.any?(["/", "?", "#"], &String.starts_with?(url, base <> &1))
  end

  defp on_root(""), do: "/"
  defp on_root("/" <> _path = path), do: path
  defp on_root(path), do: "/" <> path
end
