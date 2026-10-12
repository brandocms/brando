if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.AdminFormViews do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # 0.54 replaced each schema's admin `<Name>CreateLive` and `<Name>UpdateLive`
    # with one `<Name>FormLive`, routed with `:create` and `:update` actions.
    # Blueprints link to its route helper, `admin_<singular>_form_path`, so a
    # site still routing the old pair has listings that crash.
    #
    # A pair the generator wrote and nobody changed is replaced: the FormLive
    # comes from the `brando.gen` admin/form.ex template, the pair is deleted,
    # and its two routes point at the FormLive. "Unchanged" is a shape every
    # version of the generator produced: the `use`, the Form and Content
    # aliases, the Gettext import, and a `render/1` holding only the Form
    # live component with the generated attributes, under an optional
    # `<:header>` of text or `gettext` calls. Anything else is listed for the
    # developer. FormLives that
    # would share a route helper go to `AdminRouteScopes`.

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.IgniterConfig
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.AdminRouteScopes
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.RouteInventory
    alias Mix.Brando.Igniter.Template
    alias Rewrite.Source
    alias Sourceror.Zipper

    @actions %{"CreateLive" => :create, "UpdateLive" => :update}
    @view_definition ~r/defmodule\s+[\w.]+(?:Create|Update)Live\s+do/
    @router ~r/\b(admin_routes|use Phoenix\.Router|:router)\b/

    # The attributes the generator gave the Form component; `module`, `id`,
    # `current_user` and `schema` were always there.
    @component_attributes %{
      "module" => "{Form}",
      "entry_id" => "{@entry_id}",
      "current_user" => "{@current_user}",
      "presences" => "{@presences}",
      "schema" => "{@schema}"
    }
    @required_attributes ~w(module id current_user schema)
    @gettext_call ~S/gettext\("[^"\\]*"\)/
    # The 0.55 form shows no `<:header>`, so its text, translated or not, was
    # never an edit worth keeping. Markup in it was.
    @header_slot ~r/<:header>(?:[^<{}]|\{[^{}]*\}|<%=?(?:[^%]|%(?!>))*%>)*<\/:header>/

    def consolidate(igniter) do
      igniter = Igniter.include_glob(igniter, "lib/**/*.ex")
      sources = lib_sources(igniter)
      views = Enum.flat_map(sources, &views/1)

      if views == [] do
        igniter
      else
        routers = for {path, content} <- sources, content =~ @router, do: path
        routes = Enum.flat_map(routers, &routes(igniter, &1))
        consolidate(igniter, views, routes, routers)
      end
    end

    defp consolidate(igniter, views, routes, routers) do
      {igniter, pairs, manual} =
        views
        |> Enum.group_by(& &1.base)
        |> Enum.sort()
        |> Enum.reduce({igniter, [], []}, fn {base, pair}, {igniter, pairs, manual} ->
          case convertible(igniter, base, pair, routes) do
            {:ok, igniter, pair} -> {igniter, [pair | pairs], manual}
            {:error, igniter, reason} -> {igniter, pairs, [{base, pair, reason} | manual]}
          end
        end)

      pairs = Enum.reverse(pairs)
      renames = for pair <- pairs, view <- pair.views, into: %{}, do: {view.module, {pair.form, view.action}}

      igniter
      |> convert(pairs)
      |> rewrite_routes(routers, renames)
      |> report(pairs, Enum.reverse(manual), routes, routers)
    end

    @doc false
    # `{path, content}` for the `lib/**/*.ex` files the igniter holds.
    def lib_sources(igniter) do
      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.map(&{Source.get(&1, :path), Source.get(&1, :content)})
      |> Enum.filter(fn {path, _content} -> String.starts_with?(path, "lib/") and Path.extname(path) == ".ex" end)
      |> Enum.sort()
    end

    ## Views

    defp views({path, content}) do
      with true <- content =~ @view_definition and content =~ "BrandoAdmin.LiveView.Form",
           {:ok, ast} <- Sourceror.parse_string(content) do
        ast
        |> defined_modules()
        |> shaped()
        |> Enum.flat_map(fn {module, shape} -> view(path, module, shape) end)
      else
        _ -> []
      end
    end

    # The generator wrote one module per file.
    defp shaped([{module, body}]), do: [{module, generated_shape(body)}]
    defp shaped(modules), do: Enum.map(modules, fn {module, _body} -> {module, {:error, :shared_file}} end)

    defp view(path, module, shape) do
      case split_view_name(module) do
        {_base, nil} -> []
        {base, action} -> [%{module: module, base: base, action: action, path: path, shape: shape}]
      end
    end

    defp defined_modules(ast) do
      {_ast, modules} =
        Macro.prewalk(ast, [], fn
          {:defmodule, _, [{:__aliases__, _, parts}, [{_do, body}]]} = node, modules ->
            {node, [{Module.concat(parts), statements(body)} | modules]}

          node, modules ->
            {node, modules}
        end)

      Enum.reverse(modules)
    end

    defp statements({:__block__, _, statements}) when is_list(statements), do: statements
    defp statements(statement), do: [statement]

    defp split_view_name(module) do
      name = inspect(module)

      Enum.find_value(@actions, {name, nil}, fn {suffix, action} ->
        if String.ends_with?(name, suffix), do: {String.replace_suffix(name, suffix, ""), action}
      end)
    end

    # `{:ok, %{schema: module, gettext: module | nil, id: string}}` for a module
    # the generator wrote, `{:error, :edited}` otherwise.
    defp generated_shape(statements) do
      parts = Enum.map(statements, &statement_part/1)

      with [schema] <- for({:schema, schema} <- parts, do: schema),
           [template] <- for({:template, template} <- parts, do: template),
           {:ok, gettext} <- at_most_one(for {:gettext, backend} <- parts, do: backend),
           false <- Enum.any?(parts, &(&1 == :other)),
           {:ok, id} <- generated_template(template) do
        {:ok, %{schema: schema, gettext: gettext, id: id}}
      else
        _ -> {:error, :edited}
      end
    end

    defp at_most_one([]), do: {:ok, nil}
    defp at_most_one([one]), do: {:ok, one}
    defp at_most_one(_many), do: :error

    defp statement_part({:use, _, [module, options]}) do
      case {code(module), keyword(options)} do
        {"BrandoAdmin.LiveView.Form", [{:schema, schema}]} -> {:schema, module_name(schema)}
        {"Gettext", [{:backend, backend}]} -> {:gettext, backend}
        {"Gettext", [{:backend, backend}, {:warn, "false"}]} -> {:gettext, backend}
        _ -> :other
      end
    end

    defp statement_part({:alias, _, [module]}) do
      if code(module) in ["BrandoAdmin.Components.Form", "BrandoAdmin.Components.Content"], do: :alias, else: :other
    end

    defp statement_part({:import, _, [module | options]}) do
      with true <- String.ends_with?(code(module), ".Gettext"),
           true <- options == [] or keyword(hd(options)) == [warn: "false"] do
        {:gettext, code(module)}
      else
        _ -> :other
      end
    end

    defp statement_part({:def, _, [{:render, _, [{:assigns, _, context}]}, [{_do, body}]]}) when is_atom(context) do
      case body do
        {:sigil_H, _, [{:<<>>, _, [template]}, _modifiers]} when is_binary(template) -> {:template, template}
        _ -> :other
      end
    end

    defp statement_part(_statement), do: :other

    defp keyword(options) when is_list(options), do: Enum.map(options, fn {key, value} -> {unwrap(key), code(value)} end)
    defp keyword({:__block__, _, [options]}) when is_list(options), do: keyword(options)
    defp keyword(_options), do: nil

    defp unwrap({:__block__, _, [value]}), do: value
    defp unwrap(value), do: value

    defp code(ast), do: Sourceror.to_string(ast)

    defp short_name(module), do: module |> Module.split() |> Enum.at(-1)

    defp module_name(name), do: Module.concat([String.replace_prefix(name, "Elixir.", "")])

    defp generated_template(template) do
      rest =
        template
        |> String.replace(@header_slot, "")
        |> String.replace(
          ~r/<Content\.header(?:\s+(?:title|subtitle)=(?:\{#{@gettext_call}\}|"[^"]*"))+\s*\/>/,
          ""
        )
        |> String.trim()

      with [_, attributes] <-
             Regex.run(~r/\A<\.live_component\s+([^<>]*?)\s*(?:\/>|>\s*<\/\.live_component>)\z/, rest),
           {:ok, attributes} <- component_attributes(attributes),
           true <- Enum.all?(@required_attributes, &Map.has_key?(attributes, &1)),
           [_, id] <- Regex.run(~r/\A"([a-z][a-z0-9_]*)_form"\z/, attributes["id"]) do
        {:ok, id}
      else
        _ -> :error
      end
    end

    defp component_attributes(source) do
      pairs = Regex.scan(~r/([a-z_]+)=(\{[^{}]*\}|"[^"]*")/, source)

      cond do
        String.trim(Regex.replace(~r/([a-z_]+)=(\{[^{}]*\}|"[^"]*")/, source, "")) != "" -> :error
        Enum.any?(pairs, fn [_, name, value] -> not generated_attribute?(name, value) end) -> :error
        true -> {:ok, Map.new(pairs, fn [_, name, value] -> {name, value} end)}
      end
    end

    defp generated_attribute?("id", value), do: String.starts_with?(value, "\"")
    defp generated_attribute?(name, value), do: Map.get(@component_attributes, name) == value

    ## Routes

    # The `live` routes in a router that name an admin Create/Update LiveView.
    defp routes(igniter, path) do
      igniter.rewrite
      |> Rewrite.source!(path)
      |> Source.get(:quoted)
      |> Zipper.zip()
      |> Common.find_all(&CodeFunction.function_call?(&1, :live, [2, 3, 4]))
      |> Enum.flat_map(fn zipper ->
        case RouteInventory.at(zipper) do
          [%{kind: :live, module: module, path: route_path}] when not is_nil(module) ->
            arity = zipper |> Zipper.node() |> Sourceror.get_args() |> length()
            [%{module: module, path: route_path, router: path, arity: arity, as?: scoped_as?(zipper)}]

          _ ->
            []
        end
      end)
    end

    defp scoped_as?(nil), do: false
    defp scoped_as?(zipper), do: scope_as?(Zipper.node(zipper)) or scoped_as?(Zipper.up(zipper))

    defp scope_as?({:scope, _, arguments}) when is_list(arguments) do
      Enum.any?(arguments, fn argument ->
        argument
        |> unwrap()
        |> List.wrap()
        |> Enum.any?(fn
          {key, _value} -> unwrap(key) == :as
          _other -> false
        end)
      end)
    end

    defp scope_as?(_node), do: false

    defp rewrite_routes(igniter, routers, renames) when map_size(renames) == 0 or routers == [], do: igniter

    defp rewrite_routes(igniter, routers, renames) do
      routers
      |> Enum.filter(fn path -> Enum.any?(routes(igniter, path), &Map.has_key?(renames, &1.module)) end)
      |> Enum.reduce(igniter, fn path, igniter ->
        Igniter.update_elixir_file(igniter, path, &rewrite_routes_in(&1, renames))
      end)
    end

    defp rewrite_routes_in(zipper, renames) do
      Common.update_all_matches(zipper, &renamed_route?(&1, renames), &rewrite_route(&1, renames))
    end

    defp renamed_route?(zipper, renames) do
      CodeFunction.function_call?(zipper, :live, 2) and
        match?([%{kind: :live, module: module}] when is_map_key(renames, module), RouteInventory.at(zipper))
    end

    defp rewrite_route(zipper, renames) do
      [%{module: module}] = RouteInventory.at(zipper)
      {form, action} = Map.fetch!(renames, module)

      Zipper.update(zipper, fn {:live, meta, [path, {:__aliases__, alias_meta, parts}]} ->
        # The route keeps how it named the module: only the last segment changes.
        written = parts |> Enum.drop(-1) |> Enum.map(&to_string/1)
        short = short_name(form)
        {:__aliases__, _, renamed} = Sourceror.parse_string!(Enum.join(written ++ [short], "."))
        {:live, meta, [path, {:__aliases__, alias_meta, renamed}, {:__block__, [], [action]}]}
      end)
      |> then(&{:ok, &1})
    end

    ## Conversion

    defp convertible(igniter, base, views, routes) do
      form = Module.concat([base <> "FormLive"])
      create = Enum.find(views, &(&1.action == :create))
      update = Enum.find(views, &(&1.action == :update))

      with {:pair, %{} = create, %{} = update, [_, _]} <- {:pair, create, update, views},
           {:shape, {:ok, created}, {:ok, updated}} <- {:shape, create.shape, update.shape},
           {:schema, true} <- {:schema, created.schema == updated.schema},
           {:form, {false, igniter}} <- {:form, ProjectModule.module_exists(igniter, form)},
           {:routes, true} <- {:routes, routed?(routes, create.module) and routed?(routes, update.module)},
           {:name, true} <- {:name, generated_name?(form, updated.schema)} do
        {:ok, igniter,
         %{
           base: base,
           form: form,
           views: [create, update],
           schema: updated.schema,
           gettext: updated.gettext || created.gettext,
           id: updated.id,
           path: Path.join(Path.dirname(update.path), Macro.underscore(short_name(form)) <> ".ex")
         }}
      else
        {:pair, _create, _update, _views} -> {:error, igniter, "has no matching CreateLive/UpdateLive counterpart"}
        {:shape, _create, _update} -> {:error, igniter, "differs from what the generator wrote"}
        {:schema, false} -> {:error, igniter, "the two LiveViews name different schemas"}
        {:form, {true, igniter}} -> {:error, igniter, "#{inspect(form)} already exists"}
        {:routes, false} -> {:error, igniter, "its routes are not `live \"path\", Module` lines in the router"}
        {:name, false} -> {:error, igniter, "is not named as the generator named it (<App>Admin.<Domain>.<Name>)"}
      end
    end

    # Every generator version named the views `<App>Admin.<Domain>.<Name>CreateLive`
    # for the schema `<App>.<Domain>.<Schema>`; `convert/2` renders the
    # FormLive from those parts.
    defp generated_name?(form, schema) do
      case {Module.split(form), Module.split(schema)} do
        {[admin, domain, _view], [app, domain, _schema]} -> admin == app <> "Admin"
        _other -> false
      end
    end

    defp routed?(routes, module) do
      matching = Enum.filter(routes, &(&1.module == module))
      matching != [] and Enum.all?(matching, &(&1.arity == 2))
    end

    defp convert(igniter, pairs) do
      Enum.reduce(pairs, igniter, fn pair, igniter ->
        {namespace, [domain, short]} = pair.form |> Module.split() |> Enum.split(-2)
        admin_module = Enum.join(namespace, ".")

        binding = [
          admin_module: admin_module,
          domain: domain,
          camel_singular: String.replace_suffix(short, "FormLive", ""),
          schema_module: pair.schema,
          singular: pair.id
        ]

        case Template.render(igniter, "brando.gen", "admin/form.ex", binding) do
          {:ok, igniter, contents} ->
            contents = with_gettext(contents, admin_module, pair.gettext)

            pair.views
            |> Enum.reduce(igniter, &Igniter.rm(&2, &1.path))
            |> Files.create(pair.path, contents)
            |> keep_in_place(pair.path)

          {:error, message} ->
            Igniter.add_issue(igniter, message)
        end
      end)
    end

    # Before writing, Igniter moves every new file to the path its module name
    # maps to (`lib/app_admin/menu/…`), away from the list LiveViews under
    # `lib/app_admin/live/menu/`. Its `dont_move_files` setting, normally read
    # from `.igniter.exs`, exempts the path.
    defp keep_in_place(igniter, path) do
      config = igniter.assigns[:igniter_exs] || []
      kept = Keyword.get(config, :dont_move_files) || IgniterConfig.get(igniter, :dont_move_files)
      Igniter.assign(igniter, :igniter_exs, Keyword.put(config, :dont_move_files, Enum.uniq(kept ++ [path])))
    end

    # The view's own Gettext backend, when the template's default differs.
    defp with_gettext(contents, _admin_module, nil), do: contents

    defp with_gettext(contents, admin_module, backend),
      do: String.replace(contents, "backend: #{admin_module}.Gettext", "backend: #{backend}")

    ## Report

    defp report(igniter, pairs, manual, routes, routers) do
      igniter
      |> converted_notice(pairs)
      |> manual_warning(manual)
      |> resolve_collisions(pairs, routes, routers)
      |> reference_warning(pairs)
    end

    defp converted_notice(igniter, []), do: igniter

    defp converted_notice(igniter, pairs) do
      Igniter.add_notice(igniter, """
      Replaced the generated admin Create/Update LiveViews with one FormLive each,
      routed with `:create` and `:update` as 0.54 Blueprints link to them
      (`admin_<singular>_form_path`):

      #{Enum.map_join(pairs, "\n", &"  #{inspect(&1.form)} (#{&1.path})")}
      """)
    end

    defp manual_warning(igniter, []), do: igniter

    defp manual_warning(igniter, manual) do
      Igniter.add_warning(igniter, """
      Admin Create/Update LiveViews left for you to merge into one FormLive
      (Blueprints link to `admin_<singular>_form_path`, so their listings fail
      until then):

      #{Enum.map_join(manual, "\n", fn {base, views, reason} -> "  #{base}{Create,Update}Live (#{Enum.map_join(views, ", ", & &1.path)}): #{reason}" end)}

      For each, write `<Name>FormLive` as `mix brando.gen` does (Brando's
      priv/templates/brando.gen/admin/form.ex), route it with
      `live "/<plural>/create", <Name>FormLive, :create` and
      `live "/<plural>/update/:entry_id", <Name>FormLive, :update`, and delete
      the pair. `mix brando.doctor` checks that every Blueprint's admin route
      helpers exist.
      """)
    end

    # Phoenix names a route helper after the LiveView, so two FormLives with
    # the same name in different domains share `admin_<name>_form_path`, and
    # one Blueprint's links lead to the other's form. `AdminRouteScopes`
    # scopes the ones it can; the rest are listed.
    defp resolve_collisions(igniter, pairs, routes, routers) do
      collisions = collisions(pairs, routes)
      candidates = for {_short, pairs} <- collisions, pair <- pairs, unscoped?(pair, routes), do: pair

      {igniter, scoped, refused} =
        if candidates == [],
          do: {igniter, [], %{}},
          else: AdminRouteScopes.resolve(igniter, candidates, routers)

      scoped_forms = for scope <- scoped, form <- scope.forms, do: form
      left = pairs |> Enum.reject(&(&1.form in scoped_forms)) |> collisions(routes)

      igniter
      |> scoped_notice(scoped, pairs)
      |> collision_warning(left, refused, routers)
    end

    defp collisions(pairs, routes) do
      pairs
      |> Enum.group_by(&short_name(&1.form))
      |> Enum.filter(fn {_short, pairs} -> match?([_, _ | _], pairs) and Enum.any?(pairs, &unscoped?(&1, routes)) end)
    end

    defp form_helper(short), do: "admin_#{Macro.underscore(String.replace_suffix(short, "Live", ""))}_path"

    defp scoped_notice(igniter, [], _pairs), do: igniter

    defp scoped_notice(igniter, scoped, pairs) do
      Igniter.add_notice(igniter, """
      These FormLives shared a route helper with a FormLive in another domain, so
      the task gave their admin scope its own helper prefix and set the same
      `router_scope` on every Blueprint routed in it (its list route helper
      becomes `admin_<scope>_live_path` too):

      #{Enum.map_join(scoped, "\n", &scoped_lines(&1, pairs))}
      """)
    end

    defp scoped_lines(scope, pairs) do
      shared =
        for form <- scope.forms,
            short = short_name(form),
            do:
              "  #{form_helper(short)}: #{pairs |> Enum.filter(&(short_name(&1.form) == short)) |> Enum.map_join(", ", &inspect(&1.schema))}"

      Enum.join(
        shared ++
          [
            "    #{scope.router}:#{scope.line}: #{scope.code}, as: :#{scope.name}",
            "    router_scope: :#{scope.name} in #{Enum.map_join(scope.schemas, ", ", &inspect/1)}"
          ],
        "\n"
      )
    end

    defp collision_warning(igniter, [], _refused, _routers), do: igniter

    defp collision_warning(igniter, collisions, refused, routers) do
      Igniter.add_warning(igniter, """
      These FormLives share a route helper, so their Blueprints' links go to the
      same form:

      #{Enum.map_join(collisions, "\n", &collision_lines(igniter, &1, refused, routers))}

      Give each schema's admin routes their own helper prefix, for example
      `scope "/menu", MyAppAdmin.Menu, as: :menu do`, and set the same
      `router_scope: :menu` in the `use Brando.Blueprint` options of every
      Blueprint routed in that scope (its list route becomes
      `admin_menu_live_path` too). The task does this itself only for a plain
      `scope "/menu", MyAppAdmin.Menu do` that routes nothing but that domain's
      admin LiveViews.
      """)
    end

    defp collision_lines(igniter, {short, pairs}, refused, routers) do
      forms = Enum.map(pairs, & &1.form)

      reasons =
        for form <- forms, reason <- Map.get(refused, form, []), do: "    #{inspect(form)}: #{reason}"

      Enum.join(
        ["  #{Enum.map_join(pairs, ", ", &inspect(&1.schema))}: #{form_helper(short)}"] ++
          Enum.map(AdminRouteScopes.route_lines(igniter, routers, forms), &"    #{&1}") ++ reasons,
        "\n"
      )
    end

    # A pair routed outside a scope with `as:` gets the bare helper name.
    defp unscoped?(pair, routes) do
      modules = Enum.map(pair.views, & &1.module)
      Enum.any?(routes, &(&1.module in modules and not &1.as?))
    end

    defp reference_warning(igniter, []), do: igniter

    defp reference_warning(igniter, pairs) do
      deleted = for pair <- pairs, view <- pair.views, do: view
      deleted_paths = Enum.map(deleted, & &1.path)
      names = Enum.map(deleted, &short_name(&1.module))

      findings =
        for {path, content} <- lib_sources(igniter),
            path not in deleted_paths,
            {line, number} <- content |> String.split("\n") |> Enum.with_index(1),
            Enum.any?(names, &String.contains?(line, &1)),
            do: "  #{path}:#{number}: #{String.trim(line)}"

      case findings do
        [] ->
          igniter

        findings ->
          Igniter.add_warning(igniter, """
          These lines still name a Create/Update LiveView the task replaced with a FormLive:

          #{Enum.join(findings, "\n")}
          """)
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.AdminFormViews do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
