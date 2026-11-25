defmodule Brando.SSG.Htaccess do
  @moduledoc """
  Brando's block in a static site's `.htaccess`, for an Apache or LiteSpeed
  host serving the build, and its merge into the host's file. Reads and
  writes nothing.

  `block/4` writes what `Brando.SSG.LocalDelivery` answers for the same build:

    * the build's `404.html` for a path the host has no file for
      (`ErrorDocument`);
    * the redirect list (`Brando.SSG.RedirectList`) as rewrite rules in its
      order: the first entry that matches the decoded path, with trailing
      slashes and repeated slashes left out and its case kept, answers it,
      with its redirect (the request's query dropped, unless the target has
      its own) or `410 Gone`. A rule applies only to a request in its
      language, and a file of the build wins over an entry that is not exact;
    * `Cache-Control: no-cache` for every answer, and a year's immutable
      caching for the files the build's Vite manifest lists and their source
      maps (pages excepted), by file name.

  The rewrite rules are inside `<IfModule mod_rewrite.c>` and the headers
  inside `<IfModule mod_headers.c>`, so a host without either module serves
  the site without them. They use no `<If>` expressions, which LiteSpeed does
  not read.

  An entry whose target cannot be written so that Apache sends exactly it,
  or whose pattern Apache's regular expressions would not read as Brando
  does, is left out with a note for the build log. Nothing an editor wrote
  is written raw: a path is written as escaped bytes, and a target only of
  characters that cannot end a directive, add a flag or read as a
  backreference, with `%` escapes, spaces and other bytes percent-encoded.

  Where the host differs: a path's file is looked for under
  `DOCUMENT_ROOT`, so the block answers as `LocalDelivery` does only from the
  document root; a relative redirect target is left out (Apache sends every
  target as an absolute URL); Apache refuses an encoded slash (`%2F`) in a
  path before any rule reads it, and redirects a directory's path without
  its trailing slash to the path with one before serving its page.
  """

  alias Brando.Sites.Redirect.ValidSource
  alias Brando.SSG.RedirectList

  @begin_marker "# BEGIN Brando"
  @file_condition "RewriteCond %{ENV:BRANDO_FILE} ^1$"
  @end_marker "# END Brando"
  @immutable "public, max-age=31536000, immutable"
  # Last segment with an extension, as `Path.extname/1` reads one
  @extension "/[^/]+\\.[^/]*$"
  # Written as they are in a target; `%` escapes and other bytes are checked
  # or percent-encoded
  @target_characters ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/:?&=+,;@!*()"
  # Read by Apache's parser or by LiteSpeed's in a pattern it otherwise reads as Brando does
  @unsafe_in_pattern ~c"\"'#"

  @typedoc "A site's language codes and its default language"
  @type languages :: {[String.t()], String.t()}

  @doc """
  Brando's block for a build, from its decoded `_redirects.json` (nil when it
  has none), and notes on the entries it leaves out. `site_languages` say a
  path's language when the list names none. `not_found_page?` is whether the
  build has a `404.html`, and `manifest_files` are the files its Vite manifest
  lists, relative to its root.
  """
  @spec block(map() | nil, languages(), boolean(), [String.t()]) :: {String.t(), [String.t()]}
  def block(redirect_list, site_languages, not_found_page?, manifest_files) do
    languages = list_languages(redirect_list) || site_languages

    {rules, notes} =
      redirect_list
      |> entries()
      |> Enum.map(&entry_rules(&1, languages))
      |> Enum.reduce({[], []}, fn
        {:ok, rules}, {written, notes} -> {[rules | written], notes}
        {:note, note}, {written, notes} -> {written, [note | notes]}
        :skip, acc -> acc
      end)

    rules = Enum.reverse(rules)

    lines =
      [
        @begin_marker,
        "# Written by Brando at each deploy: what is between these two lines is replaced.",
        if(not_found_page?, do: "ErrorDocument 404 /404.html"),
        rewrite_section(rules),
        headers_section(manifest_files),
        @end_marker
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    {Enum.map_join(lines, &[&1, ?\n]), Enum.reverse(notes)}
  end

  @doc """
  `current`, the live `.htaccess` (nil when there is none), with Brando's
  block replaced by `block`: where the first block was, or after the host's
  lines when there was none. Every line outside a block comes back as it
  was. With `block` nil, the blocks are removed, and `:empty` says nothing
  but whitespace is left. `{:error, :unterminated_block}` for a
  `# BEGIN Brando` line with no `# END Brando` line after it.
  """
  @spec merge(binary() | nil, String.t() | nil) :: {:ok, binary()} | :empty | {:error, :unterminated_block}
  def merge(current, block) do
    case without_blocks(current || "") do
      {:ok, before, rest} -> merged(before, rest, block)
      :unterminated -> {:error, :unterminated_block}
    end
  end

  defp merged(before, nil, nil), do: rest_or_empty(before)
  defp merged(before, after_block, nil), do: rest_or_empty(before <> after_block)
  defp merged(before, after_block, block) when is_binary(after_block), do: {:ok, before <> block <> after_block}
  defp merged("", nil, block), do: {:ok, block}

  defp merged(before, nil, block) do
    if String.ends_with?(before, "\n"), do: {:ok, before <> block}, else: {:ok, before <> "\n" <> block}
  end

  defp rest_or_empty(rest), do: if(String.trim(rest) == "", do: :empty, else: {:ok, rest})

  @doc "Whether `content`, a live `.htaccess`, holds a whole Brando block."
  @spec block?(binary()) :: boolean()
  def block?(content), do: match?({:ok, _before, after_block} when is_binary(after_block), without_blocks(content))

  # The host's lines before the first block and those after it (nil when
  # there is no block), every block taken out
  defp without_blocks(content) do
    case content |> lines() |> Enum.reduce({:out, [], nil}, &take_line/2) do
      {:in, _before, _after} -> :unterminated
      {:out, before, nil} -> {:ok, join_reversed(before), nil}
      {:out, before, after_block} -> {:ok, join_reversed(before), join_reversed(after_block)}
    end
  end

  defp take_line(line, {state, before, after_block}) do
    case {state, marker(line)} do
      {:out, :begin} -> {:in, before, after_block || []}
      {:out, _line} when is_nil(after_block) -> {:out, [line | before], nil}
      {:out, _line} -> {:out, before, [line | after_block]}
      {:in, :end} -> {:out, before, after_block}
      {:in, _line} -> {:in, before, after_block}
    end
  end

  defp join_reversed(lines), do: lines |> Enum.reverse() |> IO.iodata_to_binary()

  # Each line with its line ending
  defp lines(""), do: []
  defp lines(content), do: Regex.split(~r/(?<=\n)/, content, trim: true)

  defp marker(line) do
    cond do
      Regex.match?(~r/\A[ \t]*# BEGIN Brando[ \t\r]*\n?\z/, line) -> :begin
      Regex.match?(~r/\A[ \t]*# END Brando[ \t\r]*\n?\z/, line) -> :end
      true -> line
    end
  end

  # -- The redirect list ----------------------------------------------------------

  # Read as `LocalDelivery` reads them
  defp list_languages(%{"languages" => [_ | _] = codes, "default_language" => default}) when is_binary(default) do
    if Enum.all?(codes, &is_binary/1), do: {codes, default}
  end

  defp list_languages(_none), do: nil

  defp entries(%{"redirects" => entries}) when is_list(entries), do: entries
  defp entries(_none), do: []

  # `LocalDelivery` matches with `pattern` alone and leaves out an entry
  # without one that compiles or without a status
  defp entry_rules(%{"pattern" => pattern, "status" => status} = entry, languages)
       when is_binary(pattern) and is_integer(status) do
    with {:ok, _regex} <- ValidSource.compile(pattern),
         {:ok, language_conditions} <- language_conditions(entry["language"], languages) do
      written_entry(entry, pattern, status, language_conditions)
    else
      _never_matches -> :skip
    end
  end

  defp entry_rules(_entry, _languages), do: :skip

  defp written_entry(entry, pattern, status, language_conditions) do
    with {:ok, condition, groups} <- path_condition(pattern),
         {:ok, substitution} <- substitution(status, entry["target"], groups) do
      matches = language_conditions ++ [condition]
      redirect = matches ++ ["RewriteRule ^ #{substitution}"]

      if entry["exact"] == true,
        do: {:ok, redirect},
        else: {:ok, [@file_condition | matches] ++ ["RewriteRule ^ - [L]" | redirect]}
    else
      {:error, reason} -> {:note, note(entry, reason)}
    end
  end

  defp note(entry, reason) do
    from = entry["source"] || entry["pattern"]
    target = if is_binary(entry["target"]), do: " → " <> shown(entry["target"]), else: ""
    ".htaccess: left out #{shown(from)}#{target}, #{reason}"
  end

  defp shown(value), do: inspect(value, printable_limit: 200)

  # A path's language is its first segment when that is one of the codes,
  # else the default
  defp language_conditions(nil, _languages), do: {:ok, []}

  defp language_conditions(language, {codes, default}) when language == default do
    case List.delete(codes, default) do
      [] -> {:ok, []}
      others -> {:ok, ["RewriteCond %{ENV:BRANDO_PATH} !^/(?:#{Enum.map_join(others, "|", &literal/1)})(?:/|$)"]}
    end
  end

  defp language_conditions(language, {codes, _default}) when is_binary(language) do
    if language in codes,
      do: {:ok, ["RewriteCond %{ENV:BRANDO_PATH} ^/#{literal(language)}(?:/|$)"]},
      else: :never
  end

  defp language_conditions(_language, _languages), do: :never

  # The condition that matches the path, and the `:name` segments it
  # captures by name, each with its group's number
  defp path_condition(pattern) do
    case RedirectList.path(pattern) do
      {path, exact?} -> {:ok, path_condition(path, exact?), path_groups(path)}
      nil -> pattern_condition(pattern)
    end
  end

  defp path_condition(path, exact?) do
    regex =
      path
      |> String.split("/")
      |> Enum.map_join("/", fn
        ":" <> _name -> "([a-z0-9_-]+)"
        segment -> literal(segment)
      end)

    "RewriteCond %{ENV:BRANDO_PATH} ^#{regex}#{if exact?, do: "$"}"
  end

  defp path_groups(path) do
    path
    |> String.split("/")
    |> Enum.flat_map(fn
      ":" <> name -> [name]
      _segment -> []
    end)
    |> Enum.with_index(1)
    |> Map.new()
  end

  # A rule written as a regular expression, as `ValidSource` expands it, in
  # PCRE as Apache reads it: its default `DOTALL` turned off, as Brando
  # compiles without it
  defp pattern_condition(pattern) do
    regex = ValidSource.expand(pattern)

    if pattern_writable?(regex),
      do: {:ok, "RewriteCond %{ENV:BRANDO_PATH} (?-s)#{regex}", {:pattern, regex}},
      else: {:error, "a pattern with characters .htaccess cannot hold"}
  end

  defp pattern_writable?(regex) do
    not String.ends_with?(regex, "\\") and
      not Enum.any?(:binary.bin_to_list(regex), &(&1 <= 0x20 or &1 == 0x7F or &1 in @unsafe_in_pattern))
  end

  # -- Targets --------------------------------------------------------------------

  defp substitution(410, _target, _groups), do: {:ok, "- [G]"}

  defp substitution(status, target, groups) when status in 300..399 and is_binary(target) do
    with :ok <- absolute(target),
         {:ok, written} <- written_target(target, groups) do
      query = if String.contains?(target, "?"), do: "", else: "?"
      {:ok, "#{written}#{query} [R=#{status},NE,L]"}
    end
  end

  defp substitution(status, nil, _groups) when status in 300..399, do: {:error, "a redirect without a target"}
  defp substitution(status, _target, _groups), do: {:error, "status #{status}, which is no redirect"}

  defp absolute("//" <> _rest), do: {:error, "a target without a scheme, which Apache sends as a path"}
  defp absolute("/" <> _rest), do: :ok

  defp absolute(target) do
    if Regex.match?(~r/\Ahttps?:\/\//i, target),
      do: :ok,
      else: {:error, "a relative target, which Apache sends against another base"}
  end

  # Each `:name` segment the pattern captures becomes its group, as
  # `Brando.Sites.Redirects.target/3` replaces it
  defp written_target(target, groups) do
    target
    |> String.split("/")
    |> Enum.reduce_while({:ok, []}, fn segment, {:ok, written} ->
      case target_segment(segment, groups) do
        {:ok, segment} -> {:cont, {:ok, [segment | written]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, segments} -> {:ok, segments |> Enum.reverse() |> Enum.join("/")}
      error -> error
    end
  end

  defp target_segment(":" <> name = segment, groups) do
    case group_number(groups, name) do
      {:ok, number} when number <= 9 -> {:ok, "%#{number}"}
      {:ok, _number} -> {:error, "a target naming a segment after the ninth group, which Apache cannot refer to"}
      :none -> target_characters(segment, [])
      :error -> {:error, "a target naming a segment of a pattern whose groups cannot be counted"}
    end
  end

  defp target_segment(segment, _groups), do: target_characters(segment, [])

  defp group_number(groups, name) when is_map(groups) do
    case Map.fetch(groups, name) do
      {:ok, number} -> {:ok, number}
      :error -> :none
    end
  end

  defp group_number({:pattern, regex}, name) do
    if name in Regex.names(Regex.compile!(regex)), do: pattern_group_number(regex, name), else: :none
  end

  defp target_characters(<<>>, written), do: {:ok, written |> Enum.reverse() |> IO.iodata_to_binary()}

  defp target_characters(<<?%, a, b, rest::binary>>, written)
       when a in ~c"0123456789abcdefABCDEF" and b in ~c"0123456789abcdefABCDEF",
       do: target_characters(rest, [<<?\\, ?%, a, b>> | written])

  defp target_characters(<<char, rest::binary>>, written) do
    cond do
      char in @target_characters -> target_characters(rest, [char | written])
      char == ?\s or char >= 0x80 -> target_characters(rest, [percent_encoded(char) | written])
      true -> {:error, "a target with #{shown(<<char>>)}, which .htaccess cannot hold as it is"}
    end
  end

  defp percent_encoded(byte), do: "\\%" <> Base.encode16(<<byte>>)

  # -- Groups of a pattern written as a regular expression --------------------------

  # The number of the named group, counted in the regular expression's text
  # and checked against the number of groups PCRE counts
  defp pattern_group_number(regex, name) do
    with {:ok, groups} <- groups(regex, []),
         true <- length(groups) == group_count(regex),
         index when is_integer(index) <- Enum.find_index(groups, &(&1 == name)) do
      {:ok, index + 1}
    else
      _uncounted -> :error
    end
  end

  # An empty group at the end, matched alone, makes PCRE return every group
  defp group_count(regex) do
    with {:ok, compiled} <- Regex.compile("(?:#{regex})|()"),
         [_whole | groups] <- Regex.run(compiled, "", capture: :all) do
      length(groups) - 1
    else
      _other -> -1
    end
  end

  # The capturing groups in order, each its name or nil. `:error` for what
  # this does not read: quoting (`\Q`), branch resets, comments, verbs and
  # options that change what counts as a group or as a character
  defp groups(<<>>, acc), do: {:ok, Enum.reverse(acc)}
  defp groups(<<"\\Q", _rest::binary>>, _acc), do: :error
  defp groups(<<"\\", _char::utf8, rest::binary>>, acc), do: groups(rest, acc)
  defp groups(<<"[^]", rest::binary>>, acc), do: groups(class(rest), acc)
  defp groups(<<"[]", rest::binary>>, acc), do: groups(class(rest), acc)
  defp groups(<<"[^", rest::binary>>, acc), do: groups(class(rest), acc)
  defp groups(<<"[", rest::binary>>, acc), do: groups(class(rest), acc)
  defp groups(<<"(*", _rest::binary>>, _acc), do: :error
  defp groups(<<"(?<=", rest::binary>>, acc), do: groups(rest, acc)
  defp groups(<<"(?<!", rest::binary>>, acc), do: groups(rest, acc)
  defp groups(<<"(?P<", rest::binary>>, acc), do: named_group(rest, ?>, acc)
  defp groups(<<"(?<", rest::binary>>, acc), do: named_group(rest, ?>, acc)
  defp groups(<<"(?'", rest::binary>>, acc), do: named_group(rest, ?', acc)
  defp groups(<<"(?", rest::binary>>, acc), do: if(plain_group?(rest), do: groups(rest, acc), else: :error)
  defp groups(<<"(", rest::binary>>, acc), do: groups(rest, [nil | acc])
  defp groups(<<_char::utf8, rest::binary>>, acc), do: groups(rest, acc)
  defp groups(_invalid, _acc), do: :error

  defp named_group(rest, close, acc) do
    case :binary.split(rest, <<close>>) do
      [name, rest] -> groups(rest, [name | acc])
      [_unclosed] -> :error
    end
  end

  # `(?:`, a lookahead, an atomic group or options, but none that reads
  # spaces and `#` as syntax, or groups as not capturing
  defp plain_group?(<<char, _rest::binary>>) when char in ~c":=!>", do: true

  defp plain_group?(rest) do
    case Regex.run(~r/\A([a-zA-Z^-]*)[:)]/, rest) do
      [_options, options] -> not String.contains?(options, ["x", "n"])
      nil -> false
    end
  end

  # What follows a character class, its first `]` taken as itself
  defp class(<<"[:", rest::binary>>) do
    case :binary.split(rest, ":]") do
      [_name, rest] -> class(rest)
      [_unclosed] -> class(rest)
    end
  end

  defp class(<<"\\", _char::utf8, rest::binary>>), do: class(rest)
  defp class(<<"]", rest::binary>>), do: rest
  defp class(<<_char::utf8, rest::binary>>), do: class(rest)
  defp class(_end_or_invalid), do: <<>>

  # -- Sections ---------------------------------------------------------------------

  defp rewrite_section([]), do: nil

  defp rewrite_section(rules) do
    file =
      if Enum.any?(rules, &match?([@file_condition | _], &1)),
        do: [
          "RewriteCond %{ENV:BRANDO_PATH} #{@extension}",
          "RewriteCond %{DOCUMENT_ROOT}%{ENV:BRANDO_PATH} -f",
          "RewriteRule ^ - [E=BRANDO_FILE:1]",
          "RewriteCond %{ENV:BRANDO_PATH} !#{@extension}",
          "RewriteCond %{DOCUMENT_ROOT}%{ENV:BRANDO_PATH}/index.html -f",
          "RewriteRule ^ - [E=BRANDO_FILE:1]"
        ],
        else: []

    [
      "<IfModule mod_rewrite.c>",
      "RewriteEngine On",
      "RewriteCond %{REQUEST_URI} (?s)^(/.*?)/*$",
      "RewriteRule ^ - [E=BRANDO_PATH:%1]",
      file,
      rules,
      "</IfModule>"
    ]
  end

  defp headers_section(manifest_files) do
    names =
      manifest_files
      |> Enum.reject(&page?/1)
      |> Enum.flat_map(&[Path.basename(&1), Path.basename(&1) <> ".map"])
      |> Enum.uniq()

    immutable =
      if names == [],
        do: [],
        else: [
          ~s[<FilesMatch "^(?:#{Enum.map_join(names, "|", &literal/1)})$">],
          ~s[Header always set Cache-Control "#{@immutable}"],
          "</FilesMatch>"
        ]

    ["<IfModule mod_headers.c>", ~s[Header always set Cache-Control "no-cache"], immutable, "</IfModule>"]
  end

  # Pages are never cached for long, as `LocalDelivery` sends them
  defp page?(file), do: MIME.from_path(file) in ["text/html", "text/markdown"]

  # A regular expression matching `text` byte for byte, of characters no
  # parser of the file reads as anything else
  defp literal(text) do
    for <<byte <- text>>, into: "" do
      if byte in ?a..?z or byte in ?A..?Z or byte in ?0..?9 or byte in ~c"_-/",
        do: <<byte>>,
        else: "\\x" <> Base.encode16(<<byte>>, case: :lower)
    end
  end
end
