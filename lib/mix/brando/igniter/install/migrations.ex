if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Install.Migrations do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Mix.Brando.Igniter.Install
    alias Mix.Brando.Install.Templates

    def preflight(igniter) do
      igniter = Igniter.include_glob(igniter, "priv/repo/migrations/*.exs")

      sources =
        Enum.filter(igniter.rewrite.sources, fn {path, _} -> String.starts_with?(path, "priv/repo/migrations/") end)

      installed? = Enum.any?(sources, fn {path, _} -> Regex.match?(~r/^\d+_brando_/, Path.basename(path)) end)

      conflicts =
        if installed? do
          []
        else
          Enum.flat_map(sources, &authentication_conflicts/1)
        end

      if conflicts == [],
        do: {:ok, igniter},
        else:
          {:error,
           "Existing migrations already create users/users_tokens: #{Enum.join(conflicts, ", ")}. Brando owns these shared public tables. Integrate the existing authentication schema and its migration history explicitly before installing; the installer cannot rename or replace existing accounts."}
    end

    defp authentication_conflicts({path, source}) do
      quoted = Rewrite.Source.get(source, :content) |> Code.string_to_quoted!()
      {_, tables} = Macro.prewalk(quoted, [], &user_table/2)
      if tables == [], do: [], else: [path]
    end

    defp user_table({:create, _, [{:table, _, [name | _]} | _]} = node, found)
         when name in [:users, :users_tokens, "users", "users_tokens"],
         do: {node, [name | found]}

    defp user_table(node, found), do: {node, found}

    def plan(igniter, project, options \\ []) do
      igniter = Igniter.include_glob(igniter, "priv/repo/{migrations,tenant_migrations}/*.exs")

      files =
        Templates.manifest()
        |> Enum.filter(fn {_format, _source, target} ->
          migration_template?(target, options)
        end)
        |> Enum.sort_by(fn {_format, _, target} -> target end)

      Enum.reduce(files, igniter, &copy_missing(&1, &2, project))
    end

    defp migration_template?(target, options) do
      if options[:upgrade] do
        Regex.match?(~r/^\d+_brando_/, Path.basename(target)) or
          String.starts_with?(target, "priv/repo/tenant_migrations/")
      else
        String.starts_with?(target, "priv/repo/") && target != "priv/repo/seeds.exs"
      end
    end

    defp copy_missing({:keep, _, _} = file, igniter, project), do: Install.copy(igniter, file, project)

    defp copy_missing({format, source, target}, igniter, project) do
      directory = Path.dirname(target)
      {version, name} = split_name(target)

      installed =
        igniter.rewrite.sources
        |> Map.keys()
        |> Enum.filter(&(Path.dirname(&1) == directory && Path.extname(&1) == ".exs"))

      matches = Enum.filter(installed, &(elem(split_name(&1), 1) == name))

      case matches do
        [_] ->
          igniter

        [] ->
          latest = installed |> Enum.map(&elem(split_name(&1), 0)) |> Enum.max(fn -> 0 end)
          target = Path.join(directory, "#{max(version, latest + 1)}_#{name}")
          Install.copy(igniter, {format, source, target}, project)

        _ ->
          Igniter.add_issue(
            igniter,
            "Multiple historical migrations match #{name}. Reconcile the duplicate files before installing."
          )
      end
    end

    defp split_name(path) do
      case Integer.parse(Path.basename(path)) do
        {version, "_" <> name} -> {version, name}
        _ -> {0, Path.basename(path)}
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.Install.Migrations do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
