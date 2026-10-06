if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Assets do
    @doc "Requests recompilation when optional Igniter support is removed."
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

    # Packages earlier backend templates installed that the current one dropped.
    @retired_backend_packages ~w(svelte-preprocess)
    # Files earlier backend templates installed that nothing reads any more.
    # vite-plugin-svelte 7 loads only svelte.config.{js,ts,mjs,mts}.
    @retired_backend_files ~w(assets/backend/svelte.config.cjs)
    # Lockfiles of the package managers earlier templates used.
    @legacy_backend_lockfiles ~w(assets/backend/yarn.lock assets/backend/package-lock.json)
    @backend_package "assets/backend/package.json"
    @backend_vite_config "assets/backend/vite.config.js"

    @doc """
    Brings an existing `assets/backend` up to the current template.

    The template's package versions, `engines` and `packageManager` replace
    the application's (its own extra packages, scripts and BrandoJS source
    stay), `vite.config.js` is replaced, files the template retired and
    yarn/npm lockfiles are removed, and the Dockerfile's `assets_backend`
    stage becomes the template's pnpm stage. CSS and every other existing
    file are kept; missing template files are created.
    """
    def upgrade(igniter, project) do
      Templates.manifest()
      |> Enum.filter(fn {_format, _source, target} -> String.starts_with?(target, "assets/backend/") end)
      |> Enum.reduce(igniter, &upgrade_asset(&1, &2, project))
      |> remove_files(@retired_backend_files ++ @legacy_backend_lockfiles)
      |> upgrade_dockerfile()
      |> Igniter.add_notice("""
      Review the assets/backend diff, then install and build the admin with pnpm:

          mix brando.assets.setup --backend-only

      Commit the assets/backend/pnpm-lock.yaml it writes; the Docker build installs from it.
      """)
    end

    defp upgrade_asset({_format, _source, target} = file, igniter, project) do
      cond do
        not Igniter.exists?(igniter, target) ->
          plan_asset(file, igniter, project)

        target == @backend_package ->
          upgrade_package(igniter, file, project)

        target == @backend_vite_config ->
          replace_file(igniter, target, template_contents(file, project))

        true ->
          igniter
      end
    end

    defp template_contents({format, source, _target}, project) do
      template = Templates.contents(format, source)
      if format == :eex, do: EEx.eval_string(template, Install.template_binding(project)), else: template
    end

    defp replace_file(igniter, path, contents) do
      Igniter.update_file(igniter, path, &Rewrite.Source.update(&1, :content, contents))
    end

    defp remove_files(igniter, paths) do
      Enum.reduce(paths, igniter, fn path, igniter ->
        if Igniter.exists?(igniter, path), do: Igniter.rm(igniter, path), else: igniter
      end)
    end

    defp upgrade_package(igniter, file, project) do
      template_json = template_contents(file, project)
      template = Jason.decode!(template_json)
      igniter = Igniter.include_existing_file(igniter, @backend_package)
      contents = igniter.rewrite |> Rewrite.source!(@backend_package) |> Rewrite.Source.get(:content)

      case Jason.decode(contents) do
        {:ok, current} when is_map(current) ->
          upgraded = upgrade_package_json(current, template)

          if upgraded == current,
            do: igniter,
            else: replace_file(igniter, @backend_package, encode_package(upgraded, [contents, template_json]))

        _ ->
          Igniter.add_issue(igniter, "#{@backend_package} must be a JSON object.")
      end
    end

    defp upgrade_package_json(current, template) do
      current
      |> merge_defaults(Map.take(template, ~w(name version type scripts)))
      |> Map.merge(Map.take(template, ~w(engines packageManager)))
      |> upgrade_dependencies(template, "dependencies")
      |> upgrade_dependencies(template, "devDependencies")
      |> upgrade_built_dependencies(template)
    end

    # The template's version wins, except for BrandoJS, whose source (a Yalc
    # copy, a link to a checkout) is the application's choice.
    defp upgrade_dependencies(package, template, key) do
      current = Map.drop(package[key] || %{}, @retired_backend_packages)
      wanted = Map.drop(template[key] || %{}, ["@brandocms/brandojs"])
      Map.put(package, key, Map.merge(current, wanted))
    end

    defp upgrade_built_dependencies(package, template) do
      built =
        ((get_in(package, ["pnpm", "onlyBuiltDependencies"]) || []) ++
           get_in(template, ["pnpm", "onlyBuiltDependencies"]))
        |> Enum.uniq()
        |> Kernel.--(@retired_backend_packages)

      Map.update(package, "pnpm", %{"onlyBuiltDependencies" => built}, &Map.put(&1, "onlyBuiltDependencies", built))
    end

    @doc false
    # The Dockerfile's `assets_backend` stage, from its FROM line up to the
    # comment block before the next stage.
    def dockerfile_stage(contents, stage) do
      lines = String.split(contents, "\n")
      start = Enum.find_index(lines, &Regex.match?(~r/^FROM\s.*\sAS\s+#{stage}\s*$/i, &1))

      if start do
        next =
          Enum.find_index(Enum.drop(lines, start + 1), &String.starts_with?(&1, "FROM ")) || length(lines) - start - 1

        stop = start + 1 + next

        stop =
          lines
          |> Enum.slice(start..(stop - 1)//1)
          |> Enum.reverse()
          |> Enum.take_while(&(String.trim(&1) == "" or String.starts_with?(String.trim(&1), "#")))
          |> length()
          |> then(&(stop - &1))

        {Enum.take(lines, start), Enum.slice(lines, start..(stop - 1)//1), Enum.drop(lines, stop)}
      end
    end

    defp upgrade_dockerfile(igniter) do
      if Igniter.exists?(igniter, "Dockerfile") do
        igniter = Igniter.include_existing_file(igniter, "Dockerfile")
        current = igniter.rewrite |> Rewrite.source!("Dockerfile") |> Rewrite.Source.get(:content)
        {_, stage, _} = dockerfile_stage(Templates.contents(:copy, "Dockerfile"), "assets_backend")

        case dockerfile_stage(current, "assets_backend") do
          {_before, ^stage, _rest} ->
            igniter

          {before, _old, rest} ->
            replace_file(igniter, "Dockerfile", Enum.join(before ++ stage ++ rest, "\n"))

          nil ->
            Igniter.add_warning(
              igniter,
              "The Dockerfile has no assets_backend stage; build the admin with pnpm as Brando's Dockerfile template does."
            )
        end
      else
        igniter
      end
    end

    defp plan_asset({format, source, target} = file, igniter, project) do
      cond do
        Path.extname(target) in [".ico", ".woff2"] ->
          binary_asset(igniter, source, target)

        Path.basename(target) == "package.json" && Igniter.exists?(igniter, target) ->
          template = Templates.contents(format, source)
          contents = if format == :eex, do: EEx.eval_string(template, Install.template_binding(project)), else: template
          merge_package(igniter, target, contents)

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

    defp merge_package(igniter, path, defaults_json) do
      defaults = Jason.decode!(defaults_json)
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
            &Rewrite.Source.update(&1, :content, encode_package(merged, [contents, defaults_json]))
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

    # Keys keep the order of the JSON documents they came from (the
    # application's file first), at every level; Jason would sort them. Keys in
    # neither document follow, sorted.
    defp encode_package(package, sources) do
      package
      |> order_like(Enum.map(sources, &Jason.decode!(&1, objects: :ordered_objects)))
      |> Jason.encode!(pretty: true)
      |> Kernel.<>("\n")
    end

    defp order_like(map, sources) when is_map(map) do
      known =
        sources
        |> Enum.flat_map(fn
          %Jason.OrderedObject{values: values} -> Enum.map(values, &elem(&1, 0))
          _other -> []
        end)
        |> Enum.uniq()
        |> Enum.filter(&Map.has_key?(map, &1))

      rest = map |> Map.keys() |> Enum.reject(&(&1 in known)) |> Enum.sort()

      (known ++ rest)
      |> Enum.map(fn key -> {key, order_like(map[key], Enum.map(sources, &child(&1, key)))} end)
      |> Jason.OrderedObject.new()
    end

    defp order_like(value, _sources), do: value

    defp child(%Jason.OrderedObject{} = object, key), do: object[key]
    defp child(_other, _key), do: nil

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
