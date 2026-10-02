# Converts the merged cover/*.coverdata into cover/lcov.info for Codecov.
#
#   MIX_ENV=test mix run --no-start .github/scripts/coverage_lcov.exs
#
# `mix test.coverage` only writes HTML, so this reads the same exports and
# writes one lcov record per source file under lib/. Modules listed in
# `test_coverage[:ignore_modules]` in mix.exs are left out, as they are there.

ignore = Keyword.get(Mix.Project.config()[:test_coverage] || [], :ignore_modules, [])
root = File.cwd!()

ignored? = fn mod ->
  Enum.any?(ignore, fn
    %Regex{} = re -> Regex.match?(re, inspect(mod))
    other -> other == mod
  end)
end

# `mix test --cover` puts OTP's :tools (which holds :cover) on the code path
# itself; `mix run` does not.
Mix.ensure_application!(:tools)
{:ok, _} = :cover.start()

for file <- Path.wildcard("cover/*.coverdata") do
  :ok = :cover.import(String.to_charlist(file))
end

source_of = fn mod ->
  with {:module, _} <- Code.ensure_loaded(mod),
       source when is_list(source) <- mod.module_info(:compile)[:source] do
    Path.relative_to(List.to_string(source), root)
  else
    _ -> nil
  end
end

records =
  :cover.imported_modules()
  |> Enum.reject(ignored?)
  |> Enum.flat_map(fn mod ->
    with source when is_binary(source) <- source_of.(mod),
         true <- String.starts_with?(source, "lib/"),
         {:ok, calls} <- :cover.analyse(mod, :calls, :line) do
      for {{_mod, line}, count} <- calls, line > 0, do: {source, line, count}
    else
      _ -> []
    end
  end)
  |> Enum.group_by(&elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})

lcov =
  records
  |> Enum.sort()
  |> Enum.map(fn {source, lines} ->
    lines =
      lines
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {line, counts} -> {line, Enum.sum(counts)} end)
      |> Enum.sort()

    hit = Enum.count(lines, fn {_, count} -> count > 0 end)

    [
      "SF:#{source}\n",
      Enum.map(lines, fn {line, count} -> "DA:#{line},#{count}\n" end),
      "LF:#{length(lines)}\nLH:#{hit}\nend_of_record\n"
    ]
  end)

File.write!("cover/lcov.info", lcov)
IO.puts("Wrote cover/lcov.info for #{map_size(records)} source files")
