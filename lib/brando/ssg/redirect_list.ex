defmodule Brando.SSG.RedirectList do
  @moduledoc """
  The redirects a static build lists in `_redirects.json`, at its root, for
  a static host to answer (`Brando.SSG.build/3`):

      {
        "version": 1,
        "redirects": [
          {"kind": "listed", "source": "/old-about", "target": "/about", "status": 301, "exact": true,
           "pattern": "/old\\\\-about$", "language": null},
          {"kind": "rule", "source": "/news/:slug", "target": "/articles/:slug", "status": 301, "exact": false,
           "pattern": "/news/:slug", "language": "en"},
          {"kind": "rule", "source": "/gone", "target": null, "status": 410, "exact": true,
           "pattern": "/gone$", "language": "en"}
        ]
      }

  The entries are in the order Brando checks them, and the first entry that
  matches a path answers it. First come the listed paths that answered a
  redirect when the build requested them (`kind` `"listed"`, `language`
  null), with the path the redirect ended at and the first redirect's status,
  when that path is a page in the build; the build stores the page it ended
  at under the listed path too, for a host that serves files before its
  redirect rules, and that page alone when the redirect ends anywhere else.
  Then the site's redirect rules (`kind` `"rule"`, Configuration → SEO),
  language by language, in the order Brando checks them for a path no page
  answers. A rule applies only to a request in its `language`.

  `source` is the path a host matches: a plain path, or one with `:name`
  segments that match one segment each (`[a-z0-9_-]+`) and stand for the
  same segment in `target`. `exact: false` matches every longer path that
  begins with `source` too, as Brando's rules do without a `$` at their end.
  A `.` in a rule with no other regular-expression character stands for
  itself in `source`. A rule written as a regular expression that is no such
  path, or whose segment would begin with an escaped `:`, has `source` null:
  only `pattern` (the rule's `from`, compiled by
  `Brando.Sites.Redirect.ValidSource.compile/1`) says what it matches.
  `status` 410 has no `target`: the path is gone. A rule that does not
  compile is left out, as is an exact rule for a path the build has a page
  for, which Brando never answers, and a redirect whose target differs from
  its source only by the query, which a host matching on the path would
  answer in a loop (`build/3` notes it).
  """

  alias Brando.Sites.Redirect.ValidSource
  alias Brando.Sites.Redirects

  @version 1
  # `.` alone is read as itself: `/old-page.html` is the page an editor means
  @metacharacters ~c"^$|?*+()[]{}"
  @whitespace_escapes %{?t => "\t", ?n => "\n", ?r => "\r", ?f => "\f", ?v => "\v"}

  @type page_redirect :: %{source: String.t(), target: String.t(), status: pos_integer()}

  @doc """
  The redirect list for `page_redirects` and the site's rules, for the
  site and environment the process works in, and notes on the redirects it
  leaves out. `built_paths` are the paths the build has a file for.
  """
  @spec build([page_redirect()], [String.t()], [{String.t(), map()}] | nil) ::
          {Jason.OrderedObject.t(), [String.t()]}
  def build(page_redirects, built_paths, rules \\ nil) do
    rules = rules || rules()
    built = MapSet.new(built_paths)

    {entries, notes} =
      (Enum.flat_map(page_redirects, &page_entry(&1, built)) ++
         Enum.flat_map(rules, fn {language, rule} -> rule_entry(rule, language, built) end))
      |> Enum.split_with(&match?(%Jason.OrderedObject{}, &1))

    {Jason.OrderedObject.new(version: @version, redirects: entries), Enum.map(notes, fn {:note, note} -> note end)}
  end

  @doc "The site's redirect rules, `{language, redirect}`, in the order Brando checks them in each language."
  @spec rules() :: [{String.t(), map()}]
  def rules do
    for language <- Brando.Languages.codes(),
        redirect <- Brando.Cache.SEO.get(language).redirects || [],
        do: {language, redirect}
  end

  # Only to a page the build has: on a host the listed path would otherwise
  # lead to a 404 where the build keeps the page it ended at
  defp page_entry(%{source: source, target: target, status: status}, built) do
    cond do
      query_only?(source, target) -> [query_only_note(source, target)]
      to_page?(target, built) -> [entry("listed", source, target, status, true, Redirects.exact_source(source), nil)]
      true -> []
    end
  end

  defp rule_entry(%{from: from, to: to, code: code}, language, built) when is_binary(from) and is_integer(code) do
    case ValidSource.compile(from) do
      {:ok, _regex} ->
        target = if code == 410 or is_nil(to), do: nil, else: Brando.HTML.replace_timestamp(to)
        source_entry(source(from), from, target, code, language, built)

      :error ->
        []
    end
  end

  defp rule_entry(_rule, _language, _built), do: []

  defp source_entry({path, exact?}, from, target, status, language, built) do
    cond do
      query_only?(path, target) -> [query_only_note(from, target)]
      exact? and MapSet.member?(built, path) -> []
      true -> [entry("rule", path, target, status, exact?, from, language)]
    end
  end

  defp source_entry(nil, from, target, status, language, _built),
    do: [entry("rule", nil, target, status, false, from, language)]

  defp entry(kind, source, target, status, exact?, pattern, language) do
    Jason.OrderedObject.new(
      kind: kind,
      source: source,
      target: target,
      status: status,
      exact: exact?,
      pattern: pattern,
      language: language
    )
  end

  # A host that matches on the path would answer the target with the same
  # redirect again
  defp query_only?(_source, nil), do: false

  defp query_only?(source, target) do
    case URI.parse(target) do
      %URI{host: nil, path: path, query: query} when is_binary(query) -> trim_slash(path || "/") == trim_slash(source)
      _other -> false
    end
  end

  defp query_only_note(source, target),
    do: {:note, "_redirects.json: left out #{source} → #{target}, which differs from its source only by the query"}

  defp to_page?(target, built) do
    case URI.parse(target) do
      %URI{host: host} when is_binary(host) -> true
      %URI{path: path} -> MapSet.member?(built, trim_slash(URI.decode(path || "/")))
    end
  end

  defp trim_slash(path), do: "/" <> Enum.join(String.split(path, "/", trim: true), "/")

  # `{path, exact?}` when `from` is a path: plain characters, characters
  # escaped as `Regex.escape/1` and `Redirects.exact_source/1` escape them, and
  # `:name` segments, with an optional `$` at its end. Nil for anything else.
  defp source(from) do
    {body, exact?} =
      if String.ends_with?(from, "$") and not String.ends_with?(from, "\\$"),
        do: {String.slice(from, 0..-2//1), true},
        else: {from, false}

    with {:ok, path} <- unescape(body, []),
         "/" <> _rest <- path do
      {path, exact?}
    else
      _not_a_path -> nil
    end
  end

  defp unescape(<<>>, acc), do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}

  # An escaped `:` that starts a segment would read as a `:name` segment
  defp unescape(<<"\\x", hex::binary-size(2), rest::binary>>, acc) do
    case {Integer.parse(hex, 16), acc} do
      {{?:, ""}, ["/" | _]} -> :error
      {{char, ""}, _acc} -> unescape(rest, [<<char::utf8>> | acc])
      _invalid -> :error
    end
  end

  defp unescape(<<"\\", escaped::utf8, rest::binary>>, acc) do
    cond do
      escaped == ?: and match?(["/" | _], acc) -> :error
      Map.has_key?(@whitespace_escapes, escaped) -> unescape(rest, [Map.fetch!(@whitespace_escapes, escaped) | acc])
      # A letter or digit after a backslash is a class or a reference
      escaped in ?a..?z or escaped in ?A..?Z or escaped in ?0..?9 -> :error
      true -> unescape(rest, [<<escaped::utf8>> | acc])
    end
  end

  defp unescape(<<char::utf8, rest::binary>>, acc) do
    if char in @metacharacters or char == ?\\, do: :error, else: unescape(rest, [<<char::utf8>> | acc])
  end

  defp unescape(_invalid, _acc), do: :error
end
