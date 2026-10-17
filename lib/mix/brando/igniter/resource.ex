if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Resource do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Input
    alias Mix.Brando.Igniter.Install.Configuration
    alias Mix.Brando.Igniter.Project
    alias Mix.Brando.Igniter.Resource.Context
    alias Mix.Brando.Igniter.Resource.Routes
    alias Mix.Brando.Igniter.Template

    def plan(igniter) do
      options = igniter.args.options

      with {:ok, name} <- Input.required(igniter.args.positional[:blueprint], "Blueprint module", options[:interactive]),
           {:ok, name} <- Input.module_name(name, "Blueprint module"),
           module = Module.concat([name]),
           :ok <- compiled_blueprint(module),
           {:ok, igniter} <- accepted_source(igniter, module),
           {:ok, igniter, options} <- Configuration.namespace_options(igniter, options),
           {:ok, igniter, project} <- Project.discover(igniter, options),
           {:ok, metadata} <- metadata(module, project, options),
           :ok <- Routes.validate_public_path(options[:public_route]),
           {:ok, igniter, metadata} <- public_metadata(igniter, metadata, options[:public_route]) do
        igniter
        |> Context.plan(metadata)
        |> files(metadata, options)
        |> Routes.plan(metadata, options)
        |> Igniter.add_notice("""
        Resource source prepared for #{inspect(module)}.
        Review your authorization policy and add a navigation entry in #{inspect(project.admin_module)}.Menus.
        Then compile, generate/review its storage migration, and run mix ecto.migrate.
        No database operation or authorization grant was performed by this generator.
        """)
        |> public_notice(metadata, options[:public_route])
      else
        {:error, %Igniter{} = igniter} -> igniter
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    defp compiled_blueprint(module) do
      if Code.ensure_loaded?(module) && function_exported?(module, :__blueprint__, 0) &&
           function_exported?(module, :__schema__, 1) do
        if Brando.Blueprint.embedded?(module),
          do:
            {:error,
             "#{inspect(module)} is an embedded Blueprint. Generate its parent resource; embedded values have no table or standalone context queries."},
          else: :ok
      else
        {:error, "#{inspect(module)} is not a compiled Brando Blueprint. Accept its source and run mix compile first."}
      end
    end

    defp accepted_source(igniter, module) do
      case ProjectModule.find_module(igniter, module) do
        {:ok, {igniter, source, _}} ->
          if source.from != :file || Rewrite.Source.updated?(source, :content) do
            {:error,
             "#{inspect(module)} has pending source changes. Accept and compile the Blueprint before generating its resource."}
          else
            {:ok, igniter}
          end

        {:error, _} ->
          {:error, "#{inspect(module)} must have source in this application."}
      end
    end

    defp metadata(module, project, options) do
      naming = module.__naming__()
      modules = module.__modules__()
      main_field = options[:main_field] || default_main_field(module)

      with true <- modules.schema == module && modules.application == project.app_module,
           {:ok, _} <- Input.identifier(naming.singular, "Blueprint singular"),
           {:ok, _} <- Input.identifier(naming.plural, "Blueprint plural"),
           {:ok, _} <- Input.module_name(naming.domain, "Blueprint domain"),
           {:ok, field} <- select_field(module, main_field) do
        {:ok,
         %{
           project: project,
           schema: module,
           context: modules.context,
           naming: naming,
           main_field: field,
           text_field?: module.__schema__(:type, field) == :string,
           status?: :status in module.__schema__(:fields),
           # Public pages show an entry by its slug when it has one.
           param: if(:slug in module.__schema__(:fields), do: "slug", else: "id"),
           primary_key: module.__schema__(:primary_key),
           id_type: module.__schema__(:type, :id),
           blocks: Enum.map(module.__blocks_fields__(), & &1.name),
           language?: :language in module.__schema__(:fields),
           alternates?: :alternate_entries in module.__schema__(:associations),
           preloads: preloads(module),
           absolute_url?: module.__has_absolute_url__(),
           required_field?:
             Enum.any?(Brando.Blueprint.Attributes.__attributes__(module), &(&1.name == field && &1.opts[:required])),
           admin_list:
             Module.concat([project.admin_module, naming.domain, Macro.camelize(naming.singular) <> "ListLive"]),
           admin_form:
             Module.concat([project.admin_module, naming.domain, Macro.camelize(naming.singular) <> "FormLive"]),
           controller:
             Module.concat([project.web_module, naming.domain, Macro.camelize(naming.singular) <> "Controller"]),
           html: Module.concat([project.web_module, naming.domain, Macro.camelize(naming.singular) <> "HTML"])
         }}
      else
        false ->
          {:error,
           "Blueprint #{inspect(module)} must belong to #{inspect(project.app_module)} and its declared schema must match its module."}

        {:error, message} ->
          {:error, message}
      end
    end

    # The show page's put_meta reads the entry's meta fields; an association
    # one of them returns must be loaded, or the layout's meta tags raise.
    defp preloads(module) do
      alternates = if :alternate_entries in module.__schema__(:associations), do: [:alternate_entries], else: []

      meta =
        try do
          for {_target, %Ecto.Association.NotLoaded{__field__: field}} <-
                Brando.Blueprint.Meta.extract_meta(module, struct(module)),
              uniq: true,
              do: field
        rescue
          _ -> if :meta_image in module.__schema__(:associations), do: [:meta_image], else: []
        end

      Enum.uniq(alternates ++ meta)
    end

    defp public_metadata(igniter, metadata, nil), do: {:ok, igniter, Map.put(metadata, :site_layouts, nil)}

    defp public_metadata(igniter, metadata, path) do
      {igniter, site_layouts} = Routes.site_layouts(igniter, metadata.project, public_route: path)

      # A consumer template copied from the default before entry pages had
      # slugs matches %{"id" => id}; its routes keep :id.
      override =
        Enum.find(
          ["controller.ex", "html.ex"],
          &Igniter.exists?(igniter, Path.join("priv/templates/brando.gen", &1))
        )

      metadata =
        Map.merge(metadata, %{
          site_layouts: site_layouts,
          template_override: override && Path.join("priv/templates/brando.gen", override),
          param: if(override, do: "id", else: metadata.param)
        })

      with :ok <- primary_key(metadata),
           {:ok, igniter, languages} <- Routes.languages(igniter, metadata) do
        {:ok, igniter, Map.put(metadata, :languages, languages)}
      end
    end

    defp primary_key(%{param: "slug"}), do: :ok

    defp primary_key(%{primary_key: [:id], id_type: type}) when type in [:id, :integer, :binary_id, Ecto.UUID],
      do: :ok

    defp primary_key(metadata) do
      {:error,
       "#{inspect(metadata.schema)}'s public pages look entries up by id, but its primary key is " <>
         "#{inspect(Enum.map(metadata.primary_key, &{&1, metadata.schema.__schema__(:type, &1)}))}: " <>
         "--public-route supports an integer or UUID primary key named :id. " <>
         "Add a slug field, or write its controller and routes by hand."}
    end

    defp default_main_field(module) do
      fields = module.__schema__(:fields)
      field = if :title in fields, do: :title, else: Enum.find(fields, &(module.__schema__(:type, &1) == :string)) || :id
      to_string(field)
    end

    defp select_field(module, name) do
      case Enum.find(module.__schema__(:fields), &(to_string(&1) == name)) do
        nil -> {:error, "--main-field #{inspect(name)} is not a persisted field of #{inspect(module)}."}
        field -> {:ok, field}
      end
    end

    defp files(igniter, metadata, options) do
      base = [
        {"admin/list.ex", module_path(metadata.admin_list)},
        {"admin/form.ex", module_path(metadata.admin_form)}
      ]

      base =
        if metadata.required_field?,
          do: base ++ [{"schema_test.exs", "test/#{Macro.underscore(metadata.schema)}_test.exs"}],
          else: base

      files =
        if options[:public_route],
          do: base ++ [{"controller.ex", module_path(metadata.controller)}, {"html.ex", module_path(metadata.html)}],
          else: base

      binding = binding(metadata, options)

      Enum.reduce(files, igniter, fn {template, path}, igniter ->
        case Template.render(igniter, "brando.gen", template, binding) do
          {:ok, igniter, contents} -> Files.create(igniter, path, contents)
          {:error, message} -> Igniter.add_issue(igniter, message)
        end
      end)
    end

    defp binding(metadata, options) do
      [
        app_module: inspect(metadata.project.app_module),
        web_module: inspect(metadata.project.web_module),
        admin_module: inspect(metadata.project.admin_module),
        schema_module: metadata.schema,
        context_module: metadata.context,
        domain: metadata.naming.domain,
        singular: metadata.naming.singular,
        plural: metadata.naming.plural,
        camel_singular: Macro.camelize(metadata.naming.singular),
        main_field: metadata.main_field,
        controller_module: metadata.controller,
        html_module: metadata.html,
        public_route: options[:public_route],
        status: metadata.status?,
        site_layouts: metadata.site_layouts,
        param: metadata.param,
        id_type: metadata.id_type,
        blocks: metadata.blocks,
        language: metadata.language?,
        alternates: metadata.alternates?,
        preloads: metadata.preloads,
        text_field: metadata.text_field?
      ]
    end

    defp public_notice(igniter, _metadata, nil),
      do: Igniter.add_notice(igniter, "Public controllers/routes are generated only with --public-route /your-path.")

    defp public_notice(igniter, metadata, path) do
      igniter
      |> Igniter.add_notice(site_notice(metadata, path))
      |> languages_notice(metadata, path)
      |> override_notice(metadata)
      |> absolute_url_notice(metadata, path)
    end

    defp languages_notice(igniter, %{languages: nil}, _path), do: igniter

    defp languages_notice(igniter, %{languages: languages}, path) do
      prefixed = Enum.map_join(languages.prefixed, ", ", &"/#{&1}#{path} for #{&1}")

      Igniter.add_notice(igniter, """
      Each language has its own routes, as the CMS pages do: #{path} for #{languages.default}#{if prefixed != "", do: ", " <> prefixed}.
      A language you add later needs its scope in the router.
      """)
    end

    defp override_notice(igniter, %{template_override: nil}), do: igniter

    defp override_notice(igniter, metadata) do
      Igniter.add_notice(igniter, """
      #{metadata.template_override} overrides the default template, so the entry pages keep the :id route
      param. To show entries by slug, update it from Brando's default, which now has the bindings
      param, site_layouts, language, preloads and blocks, and change the route to :slug.
      """)
    end

    defp site_notice(%{site_layouts: nil} = metadata, path) do
      """
      #{path} pipes through :browser only and renders in your application's layout:
      no CMS site was found (a :brando_site pipeline and #{inspect(metadata.project.web_module)}.CMS.Layouts),
      so these pages get no site assets, Brando meta tags or Brando.Plug.Lockdown.
      Run mix brando.gen.site, or wire them by hand: pipe the routes through a pipeline with
      Brando.Plug.Lockdown (it sends visitors to a route named lockdown; see Lockdown in the
      generators guide) and render with the layout of your public pages.
      """
    end

    defp site_notice(metadata, path) do
      """
      #{path} pipes through :browser and :brando_site, like the CMS pages, and renders in
      #{inspect(metadata.site_layouts)} with Brando meta tags. A missing entry renders the site's 404 page.
      """
    end

    defp absolute_url_notice(igniter, %{absolute_url?: true, languages: nil}, _path), do: igniter

    defp absolute_url_notice(igniter, %{absolute_url?: true} = metadata, path) do
      template = metadata.schema.__absolute_url_template__() |> inspect()

      if template =~ "route_i18n" or template =~ "language" do
        igniter
      else
        Igniter.add_notice(igniter, """
        #{inspect(metadata.schema)}'s absolute_url gives every language the same path, but a translation's
        page is under its language's prefix. For hreflang links, admin previews and sitemaps that work, set:

            #{absolute_url(metadata, path)}
        """)
      end
    end

    defp absolute_url_notice(igniter, metadata, path) do
      Igniter.add_notice(igniter, """
      #{inspect(metadata.schema)} has absolute_url false. To link admin previews, sitemaps and SEO to these pages, set:

          #{absolute_url(metadata, path)}
      """)
    end

    # route_i18n prefixes the entry's language as the routes do, through the
    # router helpers of the language scopes (no_article_path, and article_path).
    defp absolute_url(%{languages: nil} = metadata, path), do: ~s|absolute_url ~H"#{path}/{@entry.#{metadata.param}}"|

    defp absolute_url(metadata, _path),
      do: "absolute_url ~H|{route_i18n(@entry, :#{metadata.naming.singular}_path, :show, [@entry.#{metadata.param}])}|"

    defp module_path(module), do: "lib/#{Macro.underscore(module)}.ex"
  end
else
  defmodule Mix.Brando.Igniter.Resource do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
