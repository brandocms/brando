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
  output (not HTML text, quoted strings, comments or raw blocks):

    * a loop variable over `entries`, `for` or `tablerow`, in the loop's
      body, unless a loop or assign inside binds the name again;
    * a variable assigned an entry (`entries.first`, `entries.last`,
      `entries[0]`, `entries | first`, `entries | last`), until it is
      assigned again;
    * those paths read straight off `entries` (`entries.first.data.vars.x`);
    * the same through a variable assigned the list
      (`{% assign items = entries | reverse %}`);
    * the property path given to a filter of the entries that takes one
      (`entries | sort: "data.vars.order"` becomes `"vars.order"`); other
      quoted strings are left as they are.

  Datasource modules, whose `entries` are the datasource's records, and HEEx
  modules are left alone. Code already reading `link.vars` is left as it is,
  so the migration is safe to run again. `mix brando.doctor` lists module
  code that still reads `.data.vars` or `.data.refs` after it.

  Entries keep the HTML they rendered with the old code until they are
  rendered again: run `mix brando.entries.resave` afterwards, and restart a
  running server, which caches modules.
  """

  @liquid ~r/\{\{.*?\}\}|\{%.*?%\}/s
  @tag ~r/^\{%-?\s*(\w+)(.*?)-?%\}$/s
  @quoted ~r/('[^']*'|"[^"]*")/
  @loops ~w(for tablerow)
  @loop_ends ~w(endfor endtablerow)
  # Filters that keep a list of entries a list of entries; the first five
  # take a property path, as `sort: "data.vars.order"`
  @list_filters ~w(sort sort_natural where reject uniq reverse compact slice concat)
  # Filters that take a property path of an entry and return something else
  @path_filters ~w(map sum group_by find find_index has)
  @entry_filters ~w(first last)

  def up do
    for prefix <- prefixes(), {id, code} <- modules(prefix) do
      case rewrite(code) do
        ^code -> :ok
        fixed -> repo().query!(~s(UPDATE "#{prefix}".content_modules SET code = $1 WHERE id = $2), [fixed, id])
      end
    end
  end

  def down, do: :ok

  # Walks the Liquid tags and output in order, tracking which variables
  # hold the list of entries (`entries`, and lists assigned from it) and
  # which hold one entry (a loop variable over such a list, or one assigned
  # its first, last or nth). A loop binds its variable for its body only,
  # and an assign or capture binds a variable again from there on; inside a
  # comment or raw block nothing is read.
  @doc false
  def rewrite(code) do
    initial = %{bindings: %{"entries" => :list}, loops: [], skip: nil}

    {parts, rest_at, _state} =
      @liquid
      |> Regex.scan(code, return: :index)
      |> Enum.reduce({[], 0, initial}, fn [{start, length}], {parts, at, state} ->
        {liquid, state} = step(binary_part(code, start, length), state)
        {[liquid, binary_part(code, at, start - at) | parts], start + length, state}
      end)

    [binary_part(code, rest_at, byte_size(code) - rest_at) | parts]
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp step(liquid, %{skip: nil} = state) do
    case tag(liquid) do
      {name, _args} when name in ["comment", "raw"] ->
        {liquid, %{state | skip: "end" <> name}}

      {name, args} when name in @loops ->
        fixed = rewrite_liquid(liquid, state.bindings)

        case Regex.run(~r/^\s*(\w+)\s+in\s+([\w.\[\]]+)/, args) do
          [_, var, source] ->
            binding = if kind(source, state.bindings) == :list, do: :entry, else: :other
            loop = {var, Map.fetch(state.bindings, var)}
            {fixed, %{state | bindings: Map.put(state.bindings, var, binding), loops: [loop | state.loops]}}

          nil ->
            {fixed, %{state | loops: [nil | state.loops]}}
        end

      {name, _args} when name in @loop_ends ->
        {liquid, end_loop(state)}

      {"assign", args} ->
        fixed = rewrite_liquid(liquid, state.bindings)

        case Regex.run(~r/^\s*(\w+)\s*=(.*)$/s, args) do
          [_, var, value] -> {fixed, bind(state, var, kind(value, state.bindings))}
          nil -> {fixed, state}
        end

      {"capture", args} ->
        case Regex.run(~r/^\s*(\w+)/, args) do
          [_, var] -> {liquid, bind(state, var, :other)}
          nil -> {liquid, state}
        end

      _output_or_tag ->
        {rewrite_liquid(liquid, state.bindings), state}
    end
  end

  defp step(liquid, %{skip: end_tag} = state) do
    case tag(liquid) do
      {^end_tag, _args} -> {liquid, %{state | skip: nil}}
      _ -> {liquid, state}
    end
  end

  defp tag(liquid) do
    case Regex.run(@tag, liquid) do
      [_, name, args] -> {name, args}
      nil -> nil
    end
  end

  defp end_loop(%{loops: [{var, previous} | loops]} = state) do
    bindings =
      case previous do
        {:ok, binding} -> Map.put(state.bindings, var, binding)
        :error -> Map.delete(state.bindings, var)
      end

    %{state | bindings: bindings, loops: loops}
  end

  defp end_loop(%{loops: [nil | loops]} = state), do: %{state | loops: loops}
  defp end_loop(state), do: state

  defp bind(state, var, :other), do: %{state | bindings: Map.delete(state.bindings, var)}
  defp bind(state, var, kind), do: %{state | bindings: Map.put(state.bindings, var, kind)}

  # What an expression holds: the list of entries, one entry, or other
  defp kind(expression, bindings) do
    [head | filters] = split_filters(expression)
    filters = Enum.map(filters, &filter_name/1)

    case {reference(String.trim(head), bindings), filters} do
      {:list, filters} ->
        cond do
          Enum.all?(filters, &(&1 in @list_filters)) -> :list
          List.last(filters) in @entry_filters and Enum.all?(Enum.drop(filters, -1), &(&1 in @list_filters)) -> :entry
          true -> :other
        end

      {:entry, []} ->
        :entry

      _ ->
        :other
    end
  end

  defp reference(head, bindings) do
    case Regex.run(~r/^(\w+)((?:\.first|\.last|\[\d+\])?)$/, head) do
      [_, var, ""] -> Map.get(bindings, var)
      [_, var, _nth] -> if Map.get(bindings, var) == :list, do: :entry
      nil -> nil
    end
  end

  # `<entry>.data.vars` → `<entry>.vars` and `<list>.first.data.refs` →
  # `<list>.first.refs` outside quoted strings, and the property paths of
  # the filters applied to a list of entries.
  defp rewrite_liquid(liquid, bindings) do
    entries = for {var, :entry} <- bindings, do: Regex.escape(var)
    lists = for {var, :list} <- bindings, do: Regex.escape(var)

    liquid
    |> unquoted(fn text ->
      text
      |> replace_paths(entries, "")
      |> replace_paths(lists, "(?:\\.first|\\.last|\\[\\d+\\])")
    end)
    |> rewrite_filters(lists)
  end

  defp replace_paths(text, [], _suffix), do: text

  defp replace_paths(text, vars, suffix) do
    Regex.replace(~r/(?<![\w.])((?:#{Enum.join(vars, "|")})#{suffix})\.data\.(vars|refs)\b/, text, "\\1.\\2")
  end

  defp rewrite_filters(liquid, []), do: liquid

  defp rewrite_filters(liquid, lists) do
    case split_filters(liquid) do
      [_no_filters] ->
        liquid

      [head | filters] ->
        if Regex.match?(~r/(?<![\w.])(?:#{Enum.join(lists, "|")})\s*$/, head),
          do: Enum.join([head | rewrite_filter_paths(filters)], "|"),
          else: liquid
    end
  end

  # Rewrites the path argument of each filter while the value is still the
  # list of entries, and of the first filter that turns it into something
  # else by a path; stops at any other filter.
  defp rewrite_filter_paths([filter | rest]) do
    name = filter_name(filter)

    cond do
      name in @list_filters -> [rewrite_path_argument(filter) | rewrite_filter_paths(rest)]
      name in @path_filters -> [rewrite_path_argument(filter) | rest]
      true -> [filter | rest]
    end
  end

  defp rewrite_filter_paths([]), do: []

  defp rewrite_path_argument(filter),
    do: Regex.replace(~r/^(\s*\w+\s*:\s*)(['"])data\.(vars|refs)\./, filter, "\\1\\2\\3.")

  defp filter_name(filter) do
    case Regex.run(~r/^\s*(\w+)/, filter) do
      [_, name] -> name
      nil -> nil
    end
  end

  # Splits at each `|` outside quoted strings
  defp split_filters(text) do
    @quoted
    |> Regex.split(text, include_captures: true)
    |> Enum.reduce([""], fn
      "'" <> _ = quoted, [current | done] -> [current <> quoted | done]
      "\"" <> _ = quoted, [current | done] -> [current <> quoted | done]
      unquoted, [current | done] -> unquoted |> String.split("|") |> merge(current, done)
    end)
    |> Enum.reverse()
  end

  defp merge([first | rest], current, done), do: Enum.reverse(rest, [current <> first | done])

  defp unquoted(liquid, fun) do
    @quoted
    |> Regex.split(liquid, include_captures: true)
    |> Enum.map_join(fn
      "'" <> _ = quoted -> quoted
      "\"" <> _ = quoted -> quoted
      unquoted -> fun.(unquoted)
    end)
  end

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
