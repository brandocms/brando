if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Auxiliary do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Project.Config
    alias Igniter.Project.MixProject
    alias Mix.Brando.Igniter.Dependencies
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Install.Configuration
    alias Mix.Brando.Igniter.Mailer
    alias Mix.Brando.Igniter.Project
    alias Mix.Brando.Igniter.Template

    def plan(igniter, kind) do
      with {:ok, igniter, options} <- Configuration.namespace_options(igniter, igniter.args.options),
           {:ok, igniter, project} <- Project.discover(igniter, options) do
        generate(igniter, project, kind)
      else
        {:error, %Igniter{} = igniter} -> igniter
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    defp generate(igniter, project, :mail) do
      contact? = igniter.args.options[:contact] == true
      {igniter, mailer} = Mailer.ensure(igniter, project)

      igniter
      |> add_unless_brando_brings({:swoosh, "~> 1.0"})
      |> add_unless_brando_brings({:req, "~> 0.5 or ~> 1.0"})
      |> Config.configure_new("config.exs", :swoosh, [:api_client], Swoosh.ApiClient.Req)
      |> contact_form(project, contact?)
      |> Igniter.add_notice("""
      #{inspect(mailer)} is ready for review. Brando sends its own email (password resets, form
      notifications) through it.
      #{if contact?, do: contact_notice(project, mailer), else: ""}
      #{Mailer.remaining_setup(mailer, igniter)}
      """)
    end

    defp generate(igniter, project, :sitemap) do
      igniter
      |> copy(
        project,
        "brando.gen.sitemap",
        "lib/application_name_web/sitemap.ex",
        Module.concat(project.web_module, Sitemap)
      )
      |> Igniter.add_notice("Review the sitemap's public URL rules before calling Brando.Sitemap.generate_sitemap/0.")
    end

    defp generate(igniter, project, :authorization) do
      igniter
      |> copy(
        project,
        "brando.install",
        "lib/application_name/authorization.ex",
        Module.concat(project.app_module, Authorization)
      )
      |> Igniter.add_notice(
        "Review the generated authorization rules and add your application's content types explicitly."
      )
    end

    defp generate(igniter, project, :release) do
      igniter
      |> copy(
        project,
        "brando.install",
        "lib/application_name/release_tasks.ex",
        Module.concat(project.app_module, ReleaseTasks)
      )
      |> MixProject.update(:project, [:releases, project.otp_app], fn
        nil -> {:ok, {:code, quote(do: [include_executables_for: [:unix], steps: [:assemble, :tar]])}}
        zipper -> {:ok, zipper}
      end)
      |> Igniter.add_notice("""
      Review your runtime configuration, then build with MIX_ENV=prod mix release.
      Apply public migrations explicitly with:
        bin/#{project.otp_app} eval '#{inspect(project.app_module)}.ReleaseTasks.migrate()'
      For named environments, follow with ReleaseTasks.migrate_tenants/0.
      Deployment configuration belongs to your application; see the deployment guide.
      """)
    end

    defp contact_form(igniter, _project, false), do: igniter

    defp contact_form(igniter, project, true) do
      igniter
      |> copy(project, "brando.gen.mail", "lib/application_name/emails.ex", Module.concat(project.app_module, Emails))
      |> copy(
        project,
        "brando.gen.mail",
        "lib/application_name/contact/contact_form.ex",
        Module.concat(project.app_module, Contact.ContactForm)
      )
    end

    defp contact_notice(project, mailer) do
      """
      The contact form is in #{inspect(Module.concat(project.app_module, Contact.ContactForm))}. Pass explicit :from
      and :to addresses to #{inspect(project.app_module)}.Emails.contact/2, then deliver with #{inspect(mailer)}.
      """
    end

    # Brando depends on Swoosh and Req, so the application has them already.
    defp add_unless_brando_brings(igniter, {name, _requirement} = dependency) do
      if name in (Application.spec(:brando, :applications) || []),
        do: igniter,
        else: Dependencies.add_new(igniter, dependency)
    end

    defp copy(igniter, project, directory, name, module) do
      binding = [
        application_name: to_string(project.otp_app),
        application_module: inspect(project.app_module),
        web_module: inspect(project.web_module)
      ]

      case Template.render(igniter, directory, name, binding) do
        {:ok, igniter, contents} -> Files.create(igniter, "lib/#{Macro.underscore(module)}.ex", contents)
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.Auxiliary do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
