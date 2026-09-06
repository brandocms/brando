if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Resource do
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
           :ok <- Routes.validate_public_path(options[:public_route]) do
        igniter
        |> Context.plan(metadata)
        |> files(metadata, options)
        |> Routes.plan(metadata, options)
        |> Igniter.add_notice("""
        Resource source prepared for #{inspect(module)}.
        Review your authorization policy and add a navigation entry in #{inspect(project.admin_module)}.Menus.
        Then compile, generate/review its storage migration, and run mix ecto.migrate.
        No database operation or authorization grant was performed by this generator.
        Public controllers/routes are generated only with --public-route /your-path.
        """)
      else
        {:error, %Igniter{} = igniter} -> igniter
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    defp compiled_blueprint(module) do
      if Code.ensure_loaded?(module) && function_exported?(module, :__blueprint__, 0) &&
           function_exported?(module, :__schema__, 1) do
        :ok
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
        status: metadata.status?
      ]
    end

    defp module_path(module), do: "lib/#{Macro.underscore(module)}.ex"
  end
end
