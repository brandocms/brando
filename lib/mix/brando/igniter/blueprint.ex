if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Blueprint do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Input
    alias Mix.Brando.Igniter.Install.Configuration
    alias Mix.Brando.Igniter.Project
    alias Mix.Brando.Igniter.Template

    def plan(igniter) do
      options = igniter.args.options
      positional = igniter.args.positional

      with {:ok, domain} <- Input.required(positional[:domain], "Domain", options[:interactive]),
           {:ok, domain} <- Input.module_name(domain, "Domain"),
           {:ok, schema} <- Input.required(positional[:schema], "Schema", options[:interactive]),
           {:ok, schema} <- schema_name(schema),
           {:ok, singular} <- Input.identifier(options[:singular] || Macro.underscore(schema), "--singular"),
           {:ok, plural} <- Input.identifier(options[:plural] || singular <> "s", "--plural"),
           :ok <- distinct_names(singular, plural),
           {:ok, igniter, options} <- Configuration.namespace_options(igniter, options),
           {:ok, igniter, project} <- Project.discover(igniter, options),
           binding = template_binding(project, domain, schema, singular, plural),
           {:ok, igniter, contents} <-
             Template.render(igniter, "brando.gen.blueprint", "blueprint.ex", binding, options[:template]) do
        module = Module.concat([project.app_module, domain, schema])

        igniter
        |> Files.create("lib/#{Macro.underscore(module)}.ex", contents)
        |> Igniter.add_notice("""
        Review #{inspect(module)} and its fields, then run:
          mix compile --warnings-as-errors
          mix brando.gen #{inspect(module)}
          mix brando.gen.blueprint_migration #{inspect(module)}

        The resource generator reads compiled Blueprint metadata. Accept and compile
        this Blueprint before generating its context, admin views and migration.
        """)
      else
        {:error, %Igniter{} = igniter} -> igniter
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    defp template_binding(project, domain, schema, singular, plural) do
      [
        application_name: to_string(project.otp_app),
        app_module: inspect(project.app_module),
        web_module: inspect(project.web_module),
        admin_module: inspect(project.admin_module),
        domain: domain,
        schema: schema,
        singular: singular,
        plural: plural
      ]
    end

    defp schema_name(schema) do
      with {:ok, schema} <- Input.module_name(schema, "Schema") do
        if String.contains?(schema, "."),
          do: {:error, "Schema must be a single module segment. Put nested namespaces in Domain."},
          else: {:ok, schema}
      end
    end

    defp distinct_names(name, name), do: {:error, "--singular and --plural must be different query names."}
    defp distinct_names(_, _), do: :ok
  end
else
  defmodule Mix.Brando.Igniter.Blueprint do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
