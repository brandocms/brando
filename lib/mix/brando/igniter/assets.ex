if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Assets do
    @doc false
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Mix.Brando.Igniter.Install
    alias Mix.Brando.Install.Templates

    def plan(igniter, project, targets \\ [:backend, :frontend]) do
      prefixes = Enum.map(targets, &"assets/#{&1}/")

      Templates.manifest()
      |> Enum.filter(fn {_format, _source, target} -> String.starts_with?(target, prefixes) end)
      |> Enum.reduce(igniter, &plan_asset(&1, &2, project))
    end

    defp plan_asset({format, source, target} = file, igniter, project) do
      cond do
        Path.extname(target) in [".ico", ".woff2"] ->
          binary_asset(igniter, source, target)

        Path.basename(target) == "package.json" && Igniter.exists?(igniter, target) ->
          template = Templates.contents(format, source)
          contents = if format == :eex, do: EEx.eval_string(template, Install.template_binding(project)), else: template
          merge_package(igniter, target, Jason.decode!(contents))

        true ->
          Install.copy(igniter, file, project)
      end
    end

    defp binary_asset(igniter, source, target) do
      contents = Templates.contents(:copy, source)

      if Igniter.exists?(igniter, target) do
        igniter = Igniter.include_existing_file(igniter, target)
        existing = igniter.rewrite |> Rewrite.source!(target) |> Rewrite.Source.get(:content)

        if existing == contents do
          igniter
        else
          Igniter.add_issue(
            igniter,
            "#{target} already contains a different binary asset. Review or move it before generating."
          )
        end
      else
        digest = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)
        task = {"brando.assets.copy", [target, digest]}
        if task in igniter.tasks, do: igniter, else: Igniter.add_task(igniter, elem(task, 0), elem(task, 1))
      end
    end

    defp merge_package(igniter, path, defaults) do
      igniter = Igniter.include_existing_file(igniter, path)
      contents = igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

      with {:ok, current} when is_map(current) <- Jason.decode(contents),
           true <-
             Enum.all?(
               ~w(dependencies devDependencies scripts pnpm),
               &(not Map.has_key?(current, &1) || is_map(current[&1]))
             ) do
        merged = merge_defaults(current, defaults)

        if merged == current do
          igniter
        else
          Igniter.update_file(
            igniter,
            path,
            &Rewrite.Source.update(&1, :content, Jason.encode!(merged, pretty: true) <> "\n")
          )
        end
      else
        _ ->
          Igniter.add_issue(
            igniter,
            "#{path} must be a JSON object with object-valued dependency, script and pnpm settings."
          )
      end
    end

    defp merge_defaults(current, defaults) do
      Map.merge(defaults, current, fn _key, default, existing ->
        if is_map(default) && is_map(existing), do: merge_defaults(existing, default), else: existing
      end)
    end
  end
else
  defmodule Mix.Brando.Igniter.Assets do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
