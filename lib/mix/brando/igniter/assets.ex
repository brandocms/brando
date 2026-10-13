if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Assets do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Mix.Brando.Igniter.Install
    alias Mix.Brando.Install.Templates

    @doc """
    Runs an asset generator (`fun`, its Igniter task's `run/1`) without the
    Hex resolution listing. Igniter runs `mix deps.get` before the tasks it
    queued, here the binary asset copies, and Hex prints every locked
    package as "Unchanged:", about 120 lines that bury the generator's own
    output. `MIX_QUIET` reaches only those child `mix` commands; their
    errors still print.
    """
    def without_hex_listing(fun) do
      previous = System.get_env("MIX_QUIET")
      System.put_env("MIX_QUIET", "1")

      try do
        fun.()
      after
        if previous, do: System.put_env("MIX_QUIET", previous), else: System.delete_env("MIX_QUIET")
      end
    end

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
    @backend_postcss_config "assets/backend/postcss.config.cjs"
    # postcss.config.cjs as earlier templates wrote it, compared without
    # whitespace. One that still reads like this is the template's, and takes
    # the current one; a site's own is left alone.
    @previous_backend_postcss_configs [
      "module.exports={plugins:[require('@brandocms/europacss'),require('autoprefixer')()]}"
    ]

    @doc """
    Brings an existing `assets/backend` up to the current template.

    The template's package versions, `engines` and `packageManager` replace
    the application's (its own extra packages, scripts and BrandoJS source
    stay), `vite.config.js` is replaced, files the template retired and
    yarn/npm lockfiles are removed, and the Dockerfile's `assets_backend`
    stage becomes the template's pnpm stage. `postcss.config.cjs` is replaced
    when it is an earlier template's, unchanged. CSS and every other existing
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

        target == @backend_postcss_config ->
          upgrade_postcss_config(igniter, file, project)

        true ->
          igniter
      end
    end

    defp upgrade_postcss_config(igniter, file, project) do
      igniter = Igniter.include_existing_file(igniter, @backend_postcss_config)
      contents = igniter.rewrite |> Rewrite.source!(@backend_postcss_config) |> Rewrite.Source.get(:content)

      if String.replace(contents, ~r/\s/, "") in @previous_backend_postcss_configs,
        do: replace_file(igniter, @backend_postcss_config, template_contents(file, project)),
        else: igniter
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
      |> upgrade_overrides(template)
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

    # Pins the template needs (a dependency's broken release) win over the
    # application's own; the application's other overrides stay.
    defp upgrade_overrides(package, template) do
      case get_in(template, ["pnpm", "overrides"]) do
        wanted when is_map(wanted) and map_size(wanted) > 0 ->
          overrides = Map.merge(get_in(package, ["pnpm", "overrides"]) || %{}, wanted)
          Map.update(package, "pnpm", %{"overrides" => overrides}, &Map.put(&1, "overrides", overrides))

        _ ->
          package
      end
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
        template = Templates.contents(:copy, "Dockerfile")
        {_, stage, _} = dockerfile_stage(template, "assets_backend")

        {igniter, contents} =
          case dockerfile_stage(current, "assets_backend") do
            {_before, ^stage, _rest} ->
              {igniter, current}

            {before, _old, rest} ->
              {igniter, Enum.join(before ++ stage ++ rest, "\n")}

            nil ->
              {Igniter.add_warning(
                 igniter,
                 "The Dockerfile has no assets_backend stage; build the admin with pnpm as Brando's Dockerfile template does."
               ), current}
          end

        {igniter, contents} = upgrade_frontend_image(igniter, contents, stage_image(template, "assets_backend"))
        if contents == current, do: igniter, else: replace_file(igniter, "Dockerfile", contents)
      else
        igniter
      end
    end

    @movable_node ~r/^node:(\d+(?:\.\d+)*)(-(?:alpine|slim|bookworm|bullseye|bookworm-slim|bullseye-slim))?$/

    # The frontend is the site's own build. Its stage moves up to the admin's
    # Node major when the frontend's `engines.node` allows it (or has none),
    # for the image variants published for every major.
    defp upgrade_frontend_image(igniter, contents, wanted) do
      with image when is_binary(image) <- stage_image(contents, "assets_frontend"),
           {:ok, major} <- node_major(wanted),
           true <- older_node?(image, major) do
        range =
          case Regex.run(@movable_node, image) do
            [_, _version | _variant] -> frontend_node_range(igniter, major)
            nil -> {igniter, :kept, unmovable_reason(image)}
          end

        frontend_image(range, contents, image, wanted, major)
      else
        _ -> {igniter, contents}
      end
    end

    # A `node:<version>` image below `major`, or an image that is not one.
    defp older_node?(image, major) do
      case node_major(image) do
        {:ok, current} -> current < major
        :error -> true
      end
    end

    defp unmovable_reason("node:" <> _ = image) do
      if String.contains?(image, "@"),
        do: "It is pinned to a digest, which names one Node release.",
        else: "Its variant may not be published for newer Node majors."
    end

    defp unmovable_reason(_image), do: "It does not build on a `node:<version>` image this task can move."

    defp frontend_image({igniter, :allowed, reason}, contents, image, _wanted, major) do
      variant =
        case Regex.run(@movable_node, image) do
          [_, _version, variant] -> variant
          _no_variant -> ""
        end

      upgraded =
        Regex.replace(frontend_from(), contents, fn _line, from, _image, rest ->
          "#{from}node:#{major}#{variant}#{rest}"
        end)

      frontend_image_notice(igniter, upgraded, image, stage_image(upgraded, "assets_frontend"), reason)
    end

    defp frontend_image({igniter, :kept, reason}, contents, image, wanted, _major) do
      {Igniter.add_notice(igniter, """
       The Dockerfile's assets_frontend stage still builds on #{image}: this task updates only the assets_backend stage, which builds on #{wanted}.
       #{reason} Update that stage's FROM line once the frontend builds on #{wanted}.
       """), contents}
    end

    defp frontend_image_notice(igniter, contents, image, image, _reason), do: {igniter, contents}

    defp frontend_image_notice(igniter, contents, old, new, reason) do
      {Igniter.add_notice(igniter, """
       The Dockerfile's assets_frontend stage now builds on #{new} (was #{old}), the Node the admin builds on: #{reason}.
       Build the frontend with that Node before deploying.
       """), contents}
    end

    defp frontend_from, do: ~r/^(FROM\s+(?:--platform=\S+\s+)?)(\S+)(\s+AS\s+assets_frontend\s*)$/im

    defp node_major(image) do
      case Regex.run(~r/^node:(\d+)/, image || "") do
        [_, major] -> {:ok, String.to_integer(major)}
        nil -> :error
      end
    end

    @frontend_package "assets/frontend/package.json"

    defp frontend_node_range(igniter, major) do
      if Igniter.exists?(igniter, @frontend_package) do
        igniter = Igniter.include_existing_file(igniter, @frontend_package)
        package = igniter.rewrite |> Rewrite.source!(@frontend_package) |> Rewrite.Source.get(:content)
        node_range_status(igniter, Jason.decode(package), major)
      else
        {igniter, :kept, "There is no #{@frontend_package} to check its Node versions against."}
      end
    end

    defp node_range_status(igniter, {:ok, %{"engines" => %{"node" => range}}}, major) when is_binary(range) do
      case Mix.Brando.Igniter.NodeRange.allows_major?(range, major) do
        {:ok, true} ->
          {igniter, :allowed, "#{@frontend_package} allows it (engines.node #{inspect(range)})"}

        {:ok, false} ->
          {igniter, :kept,
           "#{@frontend_package} requires Node #{inspect(range)} (engines.node), which excludes Node #{major}."}

        :error ->
          {igniter, :kept, "This task cannot read #{@frontend_package}'s engines.node #{inspect(range)}."}
      end
    end

    defp node_range_status(igniter, {:ok, package}, _major) when is_map(package),
      do: {igniter, :allowed, "#{@frontend_package} sets no engines.node"}

    defp node_range_status(igniter, _package, _major),
      do: {igniter, :kept, "This task cannot read #{@frontend_package}."}

    defp stage_image(contents, stage) do
      contents
      |> String.split("\n")
      |> Enum.find_value(fn line ->
        case Regex.run(~r/^FROM\s+(?:--platform=\S+\s+)?(\S+)\s+AS\s+#{stage}\s*$/i, line) do
          [_, image] -> image
          _ -> nil
        end
      end)
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
