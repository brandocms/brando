if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Assets do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Mix.Brando.BrandoJS
    alias Mix.Brando.Igniter.Files
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
    # The legacy EuropaCSS PostCSS plugin and autoprefixer gave way to the
    # native compiler's Vite plugin and Lightning CSS.
    @retired_backend_packages ~w(svelte-preprocess @brandocms/europacss autoprefixer)
    # Files earlier backend templates installed that nothing reads any more.
    # vite-plugin-svelte 7 loads only svelte.config.{js,ts,mjs,mts}.
    @retired_backend_files ~w(assets/backend/svelte.config.cjs)
    # Lockfiles of the package managers earlier templates used.
    @legacy_backend_lockfiles ~w(assets/backend/yarn.lock assets/backend/package-lock.json)
    @backend_package "assets/backend/package.json"
    @backend_vite_config "assets/backend/vite.config.js"

    # The legacy EuropaCSS build's config files as earlier templates wrote
    # them, compared without whitespace. The native build reads neither: one
    # still like this is removed, a site's own is kept with a notice.
    @legacy_postcss_configs [
      "module.exports={plugins:[require('@brandocms/europacss'),require('autoprefixer')()]}",
      ~S"""
      // Europa's at-rules write rules and declarations with no source file of their
      // own: the base styles it parses from normalize.css, the output of @space,
      // @font and the like. Vite resolves a declaration's url() from its file, and
      // warns that "a PostCSS plugin did not pass the `from` option" when there is
      // none. They belong to the file whose at-rule wrote them, so each takes the
      // source of the nearest node around it that has one.
      const sourceFromFile = () => ({
        postcssPlugin: 'brando-source-from-file',
        OnceExit(root) {
          root.walk(node => {
            if (node.source?.input?.file) return
            let parent = node.parent
            while (parent && !parent.source?.input?.file) parent = parent.parent
            if (parent) node.source = parent.source
          })
        }
      })
      sourceFromFile.postcss = true

      module.exports = {
        plugins: [
          require('@brandocms/europacss'),
          require('autoprefixer')(),
          sourceFromFile()
        ]
      }
      """
    ]
    @legacy_europa_configs [
      "module.exports=require('@brandocms/brandojs/europa.config.js')",
      "module.exports=require('brandojs/europa.config.js')",
      "module.exports=require('../../../../brando/assets/europa.config.js')"
    ]
    @legacy_europa_files [
      {"assets/backend/postcss.config.cjs", @legacy_postcss_configs},
      {"assets/backend/europa.config.cjs", @legacy_europa_configs},
      {"assets/backend/europa.config.js", @legacy_europa_configs}
    ]

    @doc """
    Brings an existing `assets/backend` up to the current template.

    The template's package versions, `engines` and `packageManager` replace
    the application's (its own extra packages, scripts and BrandoJS source
    stay), `vite.config.js` is replaced, files the template retired and
    yarn/npm lockfiles are removed, and the Dockerfile's `assets_backend`
    stage becomes the template's pnpm stage, with an older or missing
    `# syntax=` directive moved to the template's; an older `twined/fehn` image
    in its `deps` stage is named in a notice, not changed. The legacy
    EuropaCSS build's `postcss.config.cjs` and `europa.config.cjs` are removed
    when they are an earlier template's, unchanged. CSS and every other existing file are kept,
    with a notice for legacy at-rules they use; missing template files,
    `europa.json5` among them, are created.
    """
    def upgrade(igniter, project) do
      Templates.manifest()
      |> Enum.filter(fn {_format, _source, target} -> String.starts_with?(target, "assets/backend/") end)
      |> Enum.reduce(igniter, &upgrade_asset(&1, &2, project))
      |> remove_files(@retired_backend_files ++ @legacy_backend_lockfiles)
      |> retire_legacy_europa_files()
      |> notice_legacy_css()
      |> upgrade_dockerfile()
      |> Igniter.add_notice("""
      Review the assets/backend diff, then install and build the admin with pnpm:

          mix brando.assets.setup --backend-only

      The admin's CSS now builds with the native EuropaCSS compiler, which pnpm installs from npm
      (@brandocms/europacss-cli and @brandocms/vite-plugin-europacss; "Native EuropaCSS" in Brando's
      guides/migrating_from_053.md). Check the application's own admin CSS with

          cd assets/backend && pnpm exec europa migrate css/app.css --from 1.0.0-beta.6 --config europa.json5 --check

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
          replace_file(igniter, target, template_contents(file, project, brando_version(igniter)))

        true ->
          igniter
      end
    end

    defp retire_legacy_europa_files(igniter) do
      Enum.reduce(@legacy_europa_files, igniter, &retire_legacy_europa_file/2)
    end

    defp retire_legacy_europa_file({path, previous}, igniter) do
      if Igniter.exists?(igniter, path) do
        {igniter, contents} = read_file(igniter, path)

        if without_whitespace(contents) in Enum.map(previous, &without_whitespace/1),
          do: Igniter.rm(igniter, path),
          else: Igniter.add_notice(igniter, own_legacy_file_notice(path))
      else
        igniter
      end
    end

    defp without_whitespace(contents), do: String.replace(contents, ~r/\s/, "")

    defp own_legacy_file_notice("assets/backend/postcss.config.cjs" = path) do
      """
      #{path} is not one Brando's templates wrote, so it is kept. The admin's vite.config.js no longer \
      loads a PostCSS config: EuropaCSS runs as a Vite plugin and Lightning CSS adds vendor prefixes. Move \
      any plugin it still needs into vite.config.js's `css.postcss`, then delete it.
      """
    end

    defp own_legacy_file_notice(path) do
      """
      #{path} is not one Brando's templates wrote, so it is kept, but the admin now builds with \
      assets/backend/europa.json5, which extends Brando's preset. Move its settings there \
      (`pnpm exec europa migrate-config #{Path.basename(path)} -o converted.json5` converts static ones), then delete it.
      """
    end

    defp backend_stylesheets(igniter) do
      igniter = Igniter.include_glob(igniter, "assets/backend/css/**/*.css")

      sources =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.filter(&String.starts_with?(&1.path, "assets/backend/css/"))
        |> Enum.sort_by(& &1.path)
        |> Enum.map(&{&1.path, Rewrite.Source.get(&1, :content)})

      {igniter, sources}
    end

    # Legacy EuropaCSS at-rules the native compiler rejects, in the
    # application's admin stylesheets.
    @removed_at_rules [
      {~r/@row\b/,
       "`@row`, which EuropaCSS no longer has: write out its 0.13 expansion (flex-wrap, child margin-left " <>
         "gutters and the nth-child resets) as \"Native EuropaCSS\" in Brando's guides/migrating_from_053.md " <>
         "shows; `gap` is not equivalent"},
      {~r/@container\s*;/, "`@container;`, which is now a CSS container query: use `@space container;`"}
    ]

    defp notice_legacy_css(igniter) do
      {igniter, sources} = backend_stylesheets(igniter)

      for {path, contents} <- sources, {pattern, advice} <- @removed_at_rules, reduce: igniter do
        igniter ->
          case line_numbers(contents, pattern) do
            [] -> igniter
            lines -> Igniter.add_notice(igniter, "#{path} (lines #{Enum.join(lines, ", ")}) uses #{advice}.")
          end
      end
    end

    defp line_numbers(contents, pattern) do
      contents
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _number} -> Regex.match?(pattern, line) end)
      |> Enum.map(&elem(&1, 1))
    end

    @doc """
    For `mix brando.migrate55`: a notice when `assets/backend/package.json`
    does not build the admin's CSS with Brando's native EuropaCSS packages
    (`Brando.EuropaCSS`), naming what differs and the two tasks that bring it
    to the template.
    """
    def notice_native_europa(igniter) do
      with true <- Igniter.exists?(igniter, @backend_package),
           {igniter, contents} = read_file(igniter, @backend_package),
           {:ok, %{} = package} <- Jason.decode(contents),
           [_ | _] = problems <- Brando.EuropaCSS.package_problems(package) do
        Igniter.add_notice(igniter, """
        assets/backend does not build the admin's CSS with Brando's native EuropaCSS packages yet:

        #{Enum.map_join(problems, "\n", &("  * " <> Brando.EuropaCSS.describe(&1)))}

        Bring it to the current template, then install and build the admin:

            mix brando.gen.backend --upgrade
            mix brando.assets.setup --backend-only

        "Admin assets" in Brando's guides/migrating_from_053.md describes both and the CSS changes the
        native compiler needs.
        """)
      else
        _ -> igniter
      end
    end

    defp read_file(igniter, path) do
      igniter = Igniter.include_existing_file(igniter, path)
      {igniter, igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)}
    end

    defp template_contents({format, source, target}, project, version) do
      template = Templates.contents(format, source)
      contents = if format == :eex, do: EEx.eval_string(template, Install.template_binding(project)), else: template

      # The template pins Brando's own version; a development version has no
      # npm release, so its admin takes BrandoJS from a checkout through Yalc.
      if target == @backend_package, do: BrandoJS.put_spec(contents, BrandoJS.spec(version)), else: contents
    end

    # The Brando version generated files pair with; tests assign another.
    defp brando_version(igniter), do: igniter.assigns[:brando_version] || Brando.version()

    defp replace_file(igniter, path, contents) do
      Igniter.update_file(igniter, path, &Rewrite.Source.update(&1, :content, contents))
    end

    defp remove_files(igniter, paths) do
      Enum.reduce(paths, igniter, fn path, igniter ->
        if Igniter.exists?(igniter, path), do: Igniter.rm(igniter, path), else: igniter
      end)
    end

    defp upgrade_package(igniter, file, project) do
      version = brando_version(igniter)
      template_json = template_contents(file, project, version)
      template = Jason.decode!(template_json)
      igniter = Igniter.include_existing_file(igniter, @backend_package)
      contents = igniter.rewrite |> Rewrite.source!(@backend_package) |> Rewrite.Source.get(:content)

      case Jason.decode(contents) do
        {:ok, current} when is_map(current) ->
          upgraded = upgrade_package_json(current, template)

          igniter =
            if upgraded == current,
              do: igniter,
              else: replace_file(igniter, @backend_package, encode_package(upgraded, [contents, template_json]))

          local_source_notice(igniter, BrandoJS.local_dependency(current), version)

        _ ->
          Igniter.add_issue(igniter, "#{@backend_package} must be a JSON object.")
      end
    end

    # A released Brando has a matching npm release of BrandoJS. An admin that
    # still takes it from a checkout keeps doing so until told otherwise.
    defp local_source_notice(igniter, spec, version) do
      if spec && not BrandoJS.development?(version) do
        Igniter.add_notice(igniter, """
        #{@backend_package} takes #{BrandoJS.package()} from a local source (#{spec}). Brando #{version}
        is published to npm with a matching BrandoJS; to install that instead, run

            mix brando.assets.setup --npm

        Keep the local source while you work on Brando itself.
        """)
      else
        igniter
      end
    end

    defp upgrade_package_json(current, template) do
      current
      |> merge_defaults(Map.take(template, ~w(name version type scripts)))
      |> Map.merge(Map.take(template, ~w(engines packageManager)))
      |> upgrade_dependencies(template)
      |> upgrade_built_dependencies(template)
      |> upgrade_overrides(template)
    end

    # The template's versions win, BrandoJS's included, except when BrandoJS
    # comes from a local source (a Yalc copy, a link to a checkout) in either
    # section: that is the application's choice. BrandoJS stays in the section
    # that declares it.
    defp upgrade_dependencies(package, template) do
      brandojs = BrandoJS.package()
      local? = BrandoJS.local_dependency(package) != nil

      package =
        Enum.reduce(~w(dependencies devDependencies), package, fn key, package ->
          current = Map.drop(package[key] || %{}, @retired_backend_packages)
          Map.put(package, key, Map.merge(current, Map.delete(template[key] || %{}, brandojs)))
        end)

      case {local?, BrandoJS.sections(package)} do
        {true, _sections} -> package
        {false, []} -> put_in(package, ["dependencies", brandojs], BrandoJS.dependency(template))
        {false, sections} -> Enum.reduce(sections, package, &put_in(&2, [&1, brandojs], BrandoJS.dependency(template)))
      end
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
              upgrade_dockerfile_syntax(igniter, current)

            {before, _old, rest} ->
              upgrade_dockerfile_syntax(igniter, Enum.join(before ++ stage ++ rest, "\n"))

            nil ->
              {Igniter.add_warning(
                 igniter,
                 "The Dockerfile has no assets_backend stage; build the admin with pnpm as Brando's Dockerfile template does."
               ), current}
          end

        {igniter, contents} = upgrade_frontend_image(igniter, contents, stage_image(template, "assets_backend"))
        igniter = notice_build_image(igniter, stage_image(contents, "deps"), stage_image(template, "deps"))
        if contents == current, do: igniter, else: replace_file(igniter, "Dockerfile", contents)
      else
        igniter
      end
    end

    @dockerfile_syntax "docker/dockerfile:1"

    # The template's assets_backend stage copies .yalc only when it exists
    # (`COPY assets/backend/.yal[c] ./.yalc/`). Old Dockerfile frontends
    # (1.0, the 1.1 releases, the experimental tags) fail or may fail a COPY
    # wildcard that matches nothing, so such a `# syntax=` directive, or a
    # missing one, moves to the template's. A leading byte order mark would
    # hide the first line's directive, and BuildKit strips it only there.
    defp upgrade_dockerfile_syntax(igniter, contents) do
      lines = contents |> String.trim_leading("\uFEFF") |> String.split("\n")
      directives = Enum.take_while(lines, &Regex.match?(~r/^#\s*\w+\s*=/, &1))
      syntax = Enum.find_index(directives, &Regex.match?(~r/^#\s*syntax\s*=/i, &1))

      frontend = syntax && directives |> Enum.at(syntax) |> String.split("=", parts: 2) |> List.last() |> String.trim()

      cond do
        is_nil(frontend) ->
          # Directives end at the first other line, a blank one included, so
          # the blank line separating them goes only before other content.
          separator = if directives == [] and hd(lines) != "", do: [""], else: []
          head = ["# syntax=#{@dockerfile_syntax}" | separator]
          {syntax_notice(igniter, "had no syntax directive"), Enum.join(head ++ lines, "\n")}

        old_dockerfile_frontend?(frontend) ->
          lines = List.replace_at(lines, syntax, "# syntax=#{@dockerfile_syntax}")
          {syntax_notice(igniter, "declared #{frontend}"), Enum.join(lines, "\n")}

        Regex.match?(~r{^(docker\.io/)?docker/dockerfile:}, frontend) ->
          {igniter, contents}

        true ->
          {Igniter.add_notice(igniter, """
           The Dockerfile builds with the Dockerfile frontend #{frontend}, which this task keeps. Its assets_backend stage copies \
           assets/backend/.yalc only when it exists (`COPY assets/backend/.yal[c] ./.yalc/`), which needs a frontend \
           that skips a COPY wildcard matching nothing, as # syntax=#{@dockerfile_syntax} does.
           """), contents}
      end
    end

    # docker/dockerfile 1.0 and the experimental channel's early tags.
    defp old_dockerfile_frontend?(frontend) do
      case Regex.run(~r{^(?:docker\.io/)?docker/dockerfile:([^@\s]+)}, frontend) do
        [_, tag] -> Regex.match?(~r/^(1\.[01]([.-].*)?|.*experimental.*)$/, tag)
        nil -> false
      end
    end

    defp syntax_notice(igniter, was) do
      Igniter.add_notice(
        igniter,
        "The Dockerfile now builds with # syntax=#{@dockerfile_syntax} (it #{was}): the assets_backend stage's optional .yalc COPY needs it."
      )
    end

    # The deps stage's fehn image decides the Elixir the release compiles on and
    # the Ubuntu release, so the glibc and OpenSSL, it runs on. The right image
    # depends on the server's Ubuntu, so this only reports an older tag.
    defp notice_build_image(igniter, current, wanted) do
      with {:ok, have} <- fehn_version(current),
           {:ok, want} <- fehn_version(wanted),
           true <- have < want do
        Igniter.add_notice(igniter, """
        The Dockerfile's deps stage builds on #{current}, older than the #{wanted} of Brando's Dockerfile, and this task does not change FROM lines. \
        An image with Elixir older than 1.18 cannot compile Brando: change the line to the variant for the server's Ubuntu release, \
        #{wanted} (or #{wanted}-noble) for Ubuntu 24.04, #{wanted}-jammy for Ubuntu 22.04 or #{wanted}-focal for Ubuntu 20.04, \
        whose Elixir and OTP are older than Brando's toolchain.#{server_notice(have, want, current, wanted)} \
        See "The Docker build" in Brando's guides/deployment.md.
        """)
      else
        _ -> igniter
      end
    end

    defp server_notice({have_major, _}, {want_major, _}, current, wanted) when have_major < want_major do
      " #{current} is Ubuntu 20.04 or older: on a 20.04 server use #{wanted}-focal and pin its Elixir and OTP, " <>
        "or better, upgrade the server to Ubuntu 22.04 or 24.04."
    end

    defp server_notice(_have, _want, _current, _wanted), do: ""

    defp fehn_version(image) when is_binary(image) do
      case Regex.run(~r{^(?:docker\.io/)?twined/fehn:(\d+)\.(\d+)(?:-[a-z]+)?$}, image) do
        [_, major, minor] -> {:ok, {String.to_integer(major), String.to_integer(minor)}}
        nil -> :error
      end
    end

    defp fehn_version(_image), do: :error

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

    defp plan_asset({_format, source, target} = file, igniter, project) do
      cond do
        Path.extname(target) == ".ico" ->
          binary_asset(igniter, source, target)

        Path.basename(target) == "package.json" && Igniter.exists?(igniter, target) ->
          merge_package(igniter, target, template_contents(file, project, brando_version(igniter)))

        target == @backend_package ->
          Files.create(igniter, target, template_contents(file, project, brando_version(igniter)))

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
        merged = merge_defaults(current, without_second_brandojs(defaults, current))

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

    # A package.json that declares BrandoJS in either section keeps that entry
    # alone, rather than gaining the template's in `dependencies` as well.
    defp without_second_brandojs(defaults, current) do
      if BrandoJS.dependency(current), do: without_brandojs(defaults), else: defaults
    end

    defp without_brandojs(package) do
      Enum.reduce(~w(dependencies devDependencies), package, fn key, package ->
        if is_map(package[key]), do: Map.update!(package, key, &Map.delete(&1, BrandoJS.package())), else: package
      end)
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
