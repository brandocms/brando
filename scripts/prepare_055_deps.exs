# Prepares an application's mix.exs for Brando 0.55 before anything resolves.
#
# Run it from the application's root, with the Brando checkout you upgrade to:
#
#     elixir /path/to/brando/scripts/prepare_055_deps.exs [--dry-run]
#         [--brando-path PATH | --brando-ref REF] [APP_DIR]
#
# It needs no resolved dependencies: it rewrites mix.exs as text and prints
# each change. From "Dependencies and toolchain" in
# guides/migrating_from_053.md: the constraints below for the packages the
# application declares, floki without `only: :test`, timex removed once lib/
# has no Timex. calls (listed otherwise), igniter for dev and test, the
# Brando dependency pointed at --brando-path or --brando-ref; and Elixir
# "~> 1.18" with `listeners: [Phoenix.CodeReloader]` in project/0. Running it
# again changes nothing. Then it lists what mix.lock still has on HTTPoison
# or hackney 1, which Brando's ex_aws 2.7 (hackney 4) cannot resolve beside.
# --dry-run prints the changes without writing them.

defmodule Brando.Prepare055Deps do
  # The guide's list (test/scripts/prepare_055_deps_test.exs keeps the two
  # in step). A declared requirement whose lower bound is already this high
  # is left alone.
  @constraints [
    phoenix: "~> 1.8.15",
    phoenix_live_view: "~> 1.2.0",
    phoenix_html: "~> 4.0",
    ecto: "~> 3.14",
    ecto_sql: "~> 3.14",
    postgrex: "~> 0.20",
    gettext: "~> 1.0",
    floki: "~> 0.32",
    swoosh: "~> 1.17",
    ex_chimp: "~> 0.2.0"
  ]

  @igniter ~s({:igniter, "~> 0.8", only: [:dev, :test]})
  @elixir "~> 1.18"

  def main(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: [dry_run: :boolean, brando_path: :string, brando_ref: :string])
    dir = List.first(args) || File.cwd!()
    mix_exs = Path.join(dir, "mix.exs")

    if !File.exists?(mix_exs), do: abort("No mix.exs in #{dir}")

    source = File.read!(mix_exs)
    {lines, changes, notes} = source |> String.split("\n") |> rewrite(dir, opts)
    result = Enum.join(lines, "\n")

    IO.puts("mix.exs:")

    case changes do
      [] -> IO.puts("  nothing to change")
      changes -> Enum.each(changes, &IO.puts("  " <> &1))
    end

    Enum.each(notes, &IO.puts("  " <> &1))

    cond do
      changes == [] -> :ok
      opts[:dry_run] -> IO.puts("\n--dry-run: mix.exs not written.")
      true -> File.write!(mix_exs, result)
    end

    report_lock(dir, result)

    IO.puts("""

    Then unlock everything and fetch:

        mix deps.unlock --all && mix deps.get
    """)
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end

  def rewrite(lines, dir, opts) do
    state = %{lines: lines, changes: [], notes: []}

    state
    |> apply_constraints()
    |> remove_timex(dir)
    |> point_brando(opts)
    |> add_igniter()
    |> project_settings()
    |> then(&{&1.lines, Enum.reverse(&1.changes), Enum.reverse(&1.notes)})
  end

  # `{:name, "requirement"…}` on a line that is not a comment.
  defp dep_regex(name), do: ~r/\{\s*:#{name}\s*,\s*"([^"]+)"([^}]*)\}/

  defp find_dep(lines, name) do
    regex = dep_regex(name)
    Enum.find_index(lines, &(not comment?(&1) and Regex.match?(regex, &1)))
  end

  defp comment?(line), do: String.starts_with?(String.trim_leading(line), "#")

  defp change(state, index, new_line) do
    old = state.lines |> Enum.at(index) |> String.trim()
    lines = List.replace_at(state.lines, index, new_line)
    %{state | lines: lines, changes: ["#{old}  →  #{String.trim(new_line)}" | state.changes]}
  end

  defp note(state, text), do: %{state | notes: [text | state.notes]}

  defp apply_constraints(state), do: Enum.reduce(@constraints, state, &constrain/2)

  defp constrain({name, requirement}, state) do
    case find_dep(state.lines, name) do
      nil ->
        state

      index ->
        line = Enum.at(state.lines, index)
        new_line = line |> raise_requirement(name, requirement) |> runtime_dep(name)
        if new_line == line, do: state, else: change(state, index, new_line)
    end
  end

  defp raise_requirement(line, name, requirement) do
    [_, current, _rest] = Regex.run(dep_regex(name), line)

    if lower_than?(current, requirement),
      do: Regex.replace(dep_regex(name), line, ~s({:#{name}, "#{requirement}"\\2}), global: false),
      else: line
  end

  # Brando uses Floki at runtime; `only: :test` makes the dependencies diverge.
  defp runtime_dep(line, :floki), do: Regex.replace(~r/,\s*only:\s*(:\w+|\[[^\]]*\])/, line, "", global: false)
  defp runtime_dep(line, _name), do: line

  # "~> 0.18" is lower than "~> 1.2.0"; ">= 0.27.0" lower than "~> 0.32".
  defp lower_than?(current, wanted) do
    case {lower_bound(current), lower_bound(wanted)} do
      {nil, _} -> true
      {current, wanted} -> Version.compare(current, wanted) == :lt
    end
  end

  defp lower_bound(requirement) do
    case Regex.run(~r/(\d+)\.(\d+)(?:\.(\d+))?/, requirement) do
      [_, major, minor] -> Version.parse!("#{major}.#{minor}.0")
      [_, major, minor, patch] -> Version.parse!("#{major}.#{minor}.#{patch}")
      nil -> nil
    end
  end

  # No Timex release accepts Gettext 1.0. Removed only when `lib/` no longer
  # calls it; otherwise the calls are listed.
  defp remove_timex(state, dir) do
    case find_dep(state.lines, :timex) do
      nil -> state
      index -> remove_timex(state, index, timex_calls(dir))
    end
  end

  defp remove_timex(state, index, []), do: remove_line(state, index)

  defp remove_timex(state, _index, calls) do
    state = note(state, "timex kept: no Timex release accepts Gettext 1.0. Replace these calls with Date, DateTime")
    state = note(state, "and Calendar, then remove it:")
    Enum.reduce(calls, state, &note(&2, "  " <> &1))
  end

  defp timex_calls(dir) do
    dir
    |> Path.join("lib/**/*.{ex,exs,heex,eex}")
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      file
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} -> String.contains?(line, "Timex.") end)
      |> Enum.map(fn {_, number} -> "#{Path.relative_to(file, dir)}:#{number}" end)
    end)
  end

  # The last element of a list has no trailing comma; the one before it then
  # loses its own.
  defp remove_line(state, index) do
    line = Enum.at(state.lines, index)
    lines = List.delete_at(state.lines, index)

    lines =
      if String.ends_with?(String.trim_trailing(line), ",") do
        lines
      else
        case previous_code_line(lines, index - 1) do
          nil -> lines
          previous -> List.update_at(lines, previous, &String.replace(&1, ~r/,(\s*)$/, "\\1"))
        end
      end

    %{state | lines: lines, changes: ["#{String.trim(line)}  →  (removed)" | state.changes]}
  end

  defp previous_code_line(_lines, index) when index < 0, do: nil

  defp previous_code_line(lines, index) do
    line = Enum.at(lines, index)
    if String.trim(line) == "" or comment?(line), do: previous_code_line(lines, index - 1), else: index
  end

  defp brando_index(lines) do
    Enum.find_index(lines, &(not comment?(&1) and Regex.match?(~r/\{\s*:brando\s*,[^}]*\}/, &1)))
  end

  defp point_brando(state, opts) do
    target =
      cond do
        opts[:brando_path] -> ~s({:brando, path: "#{opts[:brando_path]}"})
        opts[:brando_ref] -> ~s({:brando, github: "brandocms/brando", ref: "#{opts[:brando_ref]}"})
        true -> nil
      end

    case {brando_index(state.lines), target} do
      {nil, _} ->
        note(state, "No one-line {:brando, …} found: point it at Brando 0.55 by hand.")

      {_index, nil} ->
        note(state, "{:brando, …} unchanged: point it at 0.55 with --brando-path or --brando-ref, or by hand.")

      {index, target} ->
        line = Enum.at(state.lines, index)
        new_line = Regex.replace(~r/\{\s*:brando\s*,[^}]*\}/, line, target, global: false)
        if new_line == line, do: state, else: change(state, index, new_line)
    end
  end

  # Igniter is the optional Brando dependency the source tasks run on; added
  # after Brando when the application does not declare it.
  defp add_igniter(state) do
    cond do
      Enum.any?(state.lines, &(not comment?(&1) and String.contains?(&1, "{:igniter"))) ->
        state

      index = brando_index(state.lines) ->
        line = Enum.at(state.lines, index)
        indent = line |> String.replace(~r/\S.*$/, "")
        last? = not String.ends_with?(String.trim_trailing(line), ",")

        {brando_line, igniter_line} =
          if last?,
            do: {String.trim_trailing(line) <> ",", indent <> @igniter},
            else: {line, indent <> @igniter <> ","}

        lines = state.lines |> List.replace_at(index, brando_line) |> List.insert_at(index + 1, igniter_line)
        %{state | lines: lines, changes: ["(added)  →  #{@igniter}" | state.changes]}

      true ->
        note(state, "Add #{@igniter} to deps by hand.")
    end
  end

  # Brando requires Elixir 1.18, and Phoenix's code reloader a Mix listener.
  defp project_settings(state) do
    case Enum.find_index(state.lines, &Regex.match?(~r/^\s*elixir:\s*"[^"]+",\s*$/, &1)) do
      nil ->
        note(
          state,
          ~s(No `elixir: "…"` line in project/0: set elixir: "#{@elixir}" and listeners: [Phoenix.CodeReloader] by hand.)
        )

      index ->
        line = Enum.at(state.lines, index)
        [_, current] = Regex.run(~r/elixir:\s*"([^"]+)"/, line)

        state =
          if lower_than?(current, @elixir),
            do: change(state, index, String.replace(line, ~s("#{current}"), ~s("#{@elixir}"))),
            else: state

        if Enum.any?(state.lines, &Regex.match?(~r/^\s*listeners:/, &1)) do
          state
        else
          indent = String.replace(line, ~r/\S.*$/, "")
          listener = indent <> "listeners: [Phoenix.CodeReloader],"
          lines = List.insert_at(state.lines, index + 1, listener)
          %{state | lines: lines, changes: ["(added)  →  #{String.trim(listener)}" | state.changes]}
        end
    end
  end

  # What the lock still pins to HTTPoison or hackney 1. Packages the
  # application declares must move to a release on hackney 4 or Req; the rest
  # come in through other packages and are resolved again after the unlock.
  defp report_lock(dir, mix_exs) do
    lock_file = Path.join(dir, "mix.lock")

    if File.exists?(lock_file) do
      # As Mix reads it: a lock written by an older Elixir quotes its keys.
      opts = [file: lock_file, emit_warnings: false]
      {lock, _} = lock_file |> File.read!() |> Code.string_to_quoted!(opts) |> Code.eval_quoted([], opts)

      lock
      |> Enum.flat_map(fn {name, entry} -> hackney_1_deps(name, entry) end)
      |> Enum.sort()
      |> Enum.split_with(fn {name, _, _} -> declared?(mix_exs, name) end)
      |> print_lock_report()
    end
  end

  defp print_lock_report({[], []}), do: :ok

  defp print_lock_report({declared, indirect}) do
    IO.puts("\nmix.lock: on HTTPoison or hackney 1, which cannot resolve beside Brando's ex_aws 2.7 (hackney 4):")
    Enum.each(declared, fn {name, version, via} -> IO.puts("  #{name} #{version} (#{via}): #{advice(name)}") end)

    if indirect != [] do
      names = Enum.map_join(indirect, ", ", fn {name, version, _} -> "#{name} #{version}" end)
      IO.puts("  through other packages, resolved again by deps.get: #{names}")
    end
  end

  defp advice(name) do
    case @constraints[name] do
      nil -> "declared in mix.exs: move to a release on hackney 4 or Req, or replace its calls with Req"
      wanted -> "mix.exs now asks for #{wanted}"
    end
  end

  defp hackney_1_deps(name, {:hex, _package, version, _hash, _managers, deps, _repo, _outer}) do
    cond do
      name == :httpoison or (name == :hackney and Version.parse!(version).major < 4) ->
        [{name, version, "itself"}]

      via = Enum.find_value(deps, &hackney_1_dep/1) ->
        [{name, version, via}]

      true ->
        []
    end
  end

  defp hackney_1_deps(_name, _entry), do: []

  defp hackney_1_dep({:httpoison, requirement, opts}),
    do: if(!opts[:optional], do: "httpoison #{requirement}")

  defp hackney_1_dep({:hackney, requirement, opts}) do
    if !opts[:optional] and not allows_hackney_4?(requirement), do: "hackney #{requirement}"
  end

  defp hackney_1_dep(_dep), do: nil

  defp allows_hackney_4?(requirement) do
    case Version.parse_requirement(requirement) do
      {:ok, requirement} -> Version.match?("4.0.0", requirement)
      :error -> true
    end
  end

  defp declared?(mix_exs, name) do
    mix_exs |> String.split("\n") |> Enum.any?(&(not comment?(&1) and String.contains?(&1, "{:#{name},")))
  end
end

Brando.Prepare055Deps.main(System.argv())
