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
      body;
    * a variable assigned an entry (`entries.first`, `entries.last`,
      `entries[0]`, `entries | first`, `entries | last`), after the assign;
    * those paths read straight off `entries` (`entries.first.data.vars.x`);
    * the same through a variable assigned the list
      (`{% assign items = entries | reverse %}`);
    * the property path given to a filter of the entries that takes one
      (`entries | sort: "data.vars.order"` becomes `"vars.order"`); other
      quoted strings are left as they are.

  A variable an assign or capture binds that is bound elsewhere too (by a
  loop of the same name, another assign or capture, or `entries` assigned)
  is left as it is: Liquid's scopes decide which binding a read sees (an
  assign in a loop writes the outer scope, one in an `if` may not run, a
  capture renders before it binds), and a wrong guess renders nothing.
  Loops alone are followed, nested or not. The migration prints each line
  it leaves reading `.data.vars` or `.data.refs`, with the module's id, for
  a hand fix; `mix brando.doctor` lists them too.

  Datasource modules, whose `entries` are the datasource's records, and HEEx
  modules are left alone. Code already reading `link.vars` is left as it is,
  so the migration is safe to run again.

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
      fixed = rewrite(code)

      if fixed != code,
        do: repo().query!(~s(UPDATE "#{prefix}".content_modules SET code = $1 WHERE id = $2), [fixed, id])

      for {line, liquid} <- leftovers(fixed) do
        IO.warn(
          "brando_219: module ##{id} (#{prefix}) still reads #{liquid} on line #{line}, " <>
            "through a variable bound more than once or one it does not follow; rewrite it by hand",
          []
        )
      end
    end
  end

  # Liquid that still reads `.data.vars` or `.data.refs`, as `[{line, liquid}]`
  @doc false
  def leftovers(code) do
    @liquid
    |> Regex.scan(code, return: :index)
    |> Enum.filter(fn [{start, length}] ->
      binary_part(code, start, length) |> unquoted(& &1) |> then(&(&1 =~ ~r/\.data\.(?:vars|refs)\b/))
    end)
    |> Enum.map(fn [{start, length}] ->
      {code |> binary_part(0, start) |> String.split("\n") |> length(), binary_part(code, start, length)}
    end)
  end

  def down, do: :ok

  # Walks the Liquid tags and output in order, tracking which variables
  # hold the list of entries (`entries`, and lists assigned from it) and
  # which hold one entry (a loop variable over such a list, or one assigned
  # its first, last or nth). A loop binds its variable for its body; inside
  # a comment or raw block nothing is read. A name an assign or capture binds
  # and something else binds too is never taken to hold entries.
  @doc false
  def rewrite(code) do
    rebound = rebound(code)
    bindings = if "entries" in rebound, do: %{}, else: %{"entries" => :list}
    initial = %{bindings: bindings, loops: [], skip: nil, rebound: rebound}

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

  # Names an assign or capture binds that are bound elsewhere too, by a
  # loop, another assign or capture, or (for `entries`) the module. Loops
  # alone are followed: each binds its variable for its own body.
  defp rebound(code) do
    sites =
      ~r/\{%-?\s*(?:(for|tablerow)\s+(\w+)\s+in\b|(assign)\s+(\w+)\s*=|(capture)\s+(\w+))/
      |> Regex.scan(code)
      |> Enum.map(fn
        [_, _loop, name] -> {name, :loop}
        [_, "", "", _assign, name | _] -> {name, :assign}
        [_, "", "", "", "", _capture, name] -> {name, :assign}
      end)
      |> Kernel.++([{"entries", :given}])
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    for {name, kinds} <- sites, :assign in kinds and length(kinds) > 1, into: MapSet.new(), do: name
  end

  defp step(liquid, %{skip: nil} = state) do
    case tag(liquid) do
      {name, _args} when name in ["comment", "raw"] ->
        {liquid, %{state | skip: "end" <> name}}

      {name, args} when name in @loops ->
        fixed = rewrite_liquid(liquid, state.bindings)

        case Regex.run(~r/^\s*(\w+)\s+in\s+([\w.\[\]]+)/, args) do
          [_, var, source] ->
            binding =
              if kind(source, state.bindings) == :list and var not in state.rebound, do: :entry, else: :other

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

  defp bind(state, var, kind) do
    if kind == :other or var in state.rebound,
      do: %{state | bindings: Map.delete(state.bindings, var)},
      else: %{state | bindings: Map.put(state.bindings, var, kind)}
  end

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
