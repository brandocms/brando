defmodule Brando.Repo.Migrations.Brando219RewriteMultiModuleEntryPaths do
  use Ecto.Migration

  @moduledoc """
  In every site environment, rewrites multi module code that reads its
  entries' vars and refs the way Villain stored them. Before the blocks
  conversion (brando_103 to brando_133) an entry was Villain JSON with its
  vars and refs under `data`; now it is a block, with them on the block:

      {% for link in entries %}{{ link.data.vars.url }}{% endfor %}
      {% assign first_entry = entries.first %}{{ first_entry.data.refs.cover }}

  become

      {% for link in entries %}{{ link.vars.url }}{% endfor %}
      {% assign first_entry = entries.first %}{{ first_entry.refs.cover }}

  The old paths render nothing. Rewritten are, inside Liquid tags and
  output (not HTML text, not quoted strings):

    * a loop variable over `entries`, `for` or `tablerow`, in the loop's
      body;
    * a variable assigned an entry (`entries.first`, `entries.last`,
      `entries[0]`, `entries | first`, `entries | last`), after the assign;
    * those paths read straight off `entries` (`entries.first.data.vars.x`);
    * the same through a variable assigned the list
      (`{% assign items = entries | reverse %}`);
    * a property path in quotes given to a filter of `entries`
      (`entries | sort: "data.vars.order"` becomes `"vars.order"`).

  Datasource modules, whose `entries` are the datasource's records, and HEEx
  modules are left alone. Code already reading `link.vars` is left as it is,
  so the migration is safe to run again. `mix brando.doctor` lists module
  code that still reads `.data.vars` or `.data.refs` after it.

  Entries keep the HTML they rendered with the old code until they are
  rendered again: run `mix brando.entries.resave` afterwards, and restart a
  running server, which caches modules.
  """

  @tag ~r/\{%-?\s*(\w+)(.*?)-?%\}/s
  @liquid ~r/\{\{.*?\}\}|\{%.*?%\}/s
  @quoted ~r/('[^']*'|"[^"]*")/
  @entry_filters ~w(first last)
  @list_filters ~w(reverse sort sort_natural where uniq compact slice)

  def up do
    for prefix <- prefixes(), {id, code} <- modules(prefix) do
      case rewrite(code) do
        ^code -> :ok
        fixed -> repo().query!(~s(UPDATE "#{prefix}".content_modules SET code = $1 WHERE id = $2), [fixed, id])
      end
    end
  end

  def down, do: :ok

  @doc false
  def rewrite(code) do
    lists = list_aliases(code)
    sources = ["entries" | MapSet.to_list(lists)]

    code
    |> rewrite_assigned_entries(sources)
    |> rewrite_loops(sources, 0)
    |> rewrite_liquid(fn liquid -> liquid |> rewrite_paths(sources_pattern(sources)) |> rewrite_filter_paths(sources) end)
  end

  # Variables assigned the list of entries, through filters that keep it a
  # list of entries: `{% assign items = entries | reverse %}`.
  defp list_aliases(code) do
    Enum.reduce(Regex.scan(~r/\{%-?\s*assign\s+(\w+)\s*=\s*(\w+)((?:\s*\|[^%|]*)*)\s*-?%\}/, code), MapSet.new(), fn
      [_, var, source, filters], acc ->
        if (source == "entries" or MapSet.member?(acc, source)) and list_filters?(filters),
          do: MapSet.put(acc, var),
          else: acc
    end)
  end

  defp list_filters?(filters) do
    filters
    |> String.split("|")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.all?(&(filter_name(&1) in @list_filters))
  end

  defp filter_name(filter), do: filter |> String.split(~r/[\s:]/, parts: 2) |> hd()

  # A variable assigned one entry is rewritten from its assign to the end of
  # the code.
  defp rewrite_assigned_entries(code, sources) do
    source = Enum.map_join(sources, "|", &Regex.escape/1)

    entry =
      ~r/\{%-?\s*assign\s+(\w+)\s*=\s*(?:(?:#{source})(?:\.first|\.last|\[\d+\])|(?:#{source})\s*\|\s*(?:#{Enum.join(@entry_filters, "|")}))\s*-?%\}/

    case Regex.scan(entry, code, return: :index) do
      [] ->
        code

      matches ->
        Enum.reduce(Enum.reverse(matches), code, fn [{start, length}, var], code ->
          from = start + length
          rest = binary_part(code, from, byte_size(code) - from)
          var = part(code, var)
          binary_part(code, 0, from) <> rewrite_liquid(rest, &rewrite_paths(&1, Regex.escape(var)))
        end)
    end
  end

  # Rewrites the body of the `nth` loop over the entries and moves on. Loops
  # are found again after every rewrite, because rewriting a body shifts the
  # offsets after it.
  defp rewrite_loops(code, sources, nth) do
    tags = Regex.scan(@tag, code, return: :index)

    case tags |> Enum.with_index() |> Enum.filter(&loop_tag?(code, &1)) |> Enum.at(nth) do
      nil ->
        code

      {[{tag_start, tag_length} | _] = tag, index} ->
        with var when is_binary(var) <- entry_loop_var(code, tag, sources),
             {body_start, body_end} <- body(code, tags, index, tag_start + tag_length) do
          body = binary_part(code, body_start, body_end - body_start)
          fixed = rewrite_liquid(body, &rewrite_paths(&1, Regex.escape(var)))
          code = binary_part(code, 0, body_start) <> fixed <> binary_part(code, body_end, byte_size(code) - body_end)
          rewrite_loops(code, sources, nth + 1)
        else
          _ -> rewrite_loops(code, sources, nth + 1)
        end
    end
  end

  defp loop_tag?(code, {[_, name | _], _}), do: part(code, name) in ["for", "tablerow"]

  defp entry_loop_var(code, [_, _, args], sources) do
    case Regex.run(~r/^\s*(\w+)\s+in\s+(\w+)(?=\s|$)/, part(code, args)) do
      [_, var, source] -> if source in sources, do: var
      nil -> nil
    end
  end

  # The body runs from the end of the loop tag to its matching end tag.
  defp body(code, tags, index, body_start) do
    tags
    |> Enum.drop(index + 1)
    |> Enum.reduce_while(1, fn [{start, _}, name | _], depth ->
      case part(code, name) do
        tag when tag in ["for", "tablerow"] -> {:cont, depth + 1}
        tag when tag in ["endfor", "endtablerow"] and depth == 1 -> {:halt, {body_start, start}}
        tag when tag in ["endfor", "endtablerow"] -> {:cont, depth - 1}
        _ -> {:cont, depth}
      end
    end)
    |> case do
      {_, _} = body -> body
      _unclosed -> nil
    end
  end

  defp rewrite_liquid(code, fun), do: Regex.replace(@liquid, code, fn liquid -> fun.(liquid) end)

  defp sources_pattern(sources) do
    "(?:" <> Enum.map_join(sources, "|", &Regex.escape/1) <> ")(?:\\.first|\\.last|\\[\\d+\\])"
  end

  # `<var>.data.vars` → `<var>.vars`, `<var>.data.refs` → `<var>.refs`, outside
  # quoted strings.
  defp rewrite_paths(liquid, var) do
    unquoted(liquid, &Regex.replace(~r/(?<![\w.])(#{var})\.data\.(vars|refs)\b/, &1, "\\1.\\2"))
  end

  # `entries | sort: "data.vars.order"` → `entries | sort: "vars.order"`
  defp rewrite_filter_paths(liquid, sources) do
    if Regex.match?(~r/(?<![\w.])(?:#{Enum.map_join(sources, "|", &Regex.escape/1)})\s*\|/, liquid),
      do: Regex.replace(~r/(['"])data\.(vars|refs)\./, liquid, "\\1\\2."),
      else: liquid
  end

  defp unquoted(liquid, fun) do
    @quoted
    |> Regex.split(liquid, include_captures: true)
    |> Enum.map_join(fn
      "'" <> _ = quoted -> quoted
      "\"" <> _ = quoted -> quoted
      unquoted -> fun.(unquoted)
    end)
  end

  defp part(code, {start, length}), do: binary_part(code, start, length)

  defp modules(prefix) do
    %{rows: rows} =
      repo().query!("""
      SELECT id, code FROM "#{prefix}".content_modules
      WHERE code ~ 'data\\.(vars|refs)'
      AND datasource IS NOT TRUE
      AND type IS DISTINCT FROM 'heex'
      ORDER BY id
      """)

    Enum.map(rows, fn [id, code] -> {id, code} end)
  end

  # Every site environment, or only the one named by the migrator's prefix:
  # `Brando.Environments.ArchiveUpgrade` runs this again in an archive
  # restored from before it ran.
  defp prefixes do
    case prefix() do
      "tenant_" <> _ = environment ->
        [environment]

      _ ->
        %{rows: rows} =
          repo().query!(
            "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
          )

        Enum.map(rows, &hd/1)
    end
  end
end
