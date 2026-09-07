if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Auxiliary do
    @doc false
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Project.Config
    alias Igniter.Project.MixProject
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Dependencies
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Install.Configuration
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
      mailer = Module.concat(project.app_module, Mailer)

      # Phoenix may already have supplied a configured mailer. Reuse it.
      igniter =
        case ProjectModule.find_module(igniter, mailer) do
          {:ok, {igniter, _, _}} -> igniter
          {:error, igniter} -> copy(igniter, project, "brando.gen.mail", "lib/application_name/mailer.ex", mailer)
        end

      igniter
      |> Dependencies.add_new({:swoosh, "~> 1.0"})
      |> Dependencies.add_new({:req, "~> 0.5 or ~> 1.0"})
      |> copy(project, "brando.gen.mail", "lib/application_name/emails.ex", Module.concat(project.app_module, Emails))
      |> copy(
        project,
        "brando.gen.mail",
        "lib/application_name/contact/contact_form.ex",
        Module.concat(project.app_module, Contact.ContactForm)
      )
      |> Config.configure_new("dev.exs", project.otp_app, [mailer, :adapter], Swoosh.Adapters.Local)
      |> Config.configure_new("test.exs", project.otp_app, [mailer, :adapter], Swoosh.Adapters.Test)
      |> Config.configure_new("config.exs", :swoosh, [:api_client], Swoosh.ApiClient.Req)
      |> Igniter.add_notice("""
      Mail helpers are ready for review. Pass explicit :from and :to addresses to
      #{inspect(project.app_module)}.Emails.contact/2, then deliver with #{inspect(mailer)}.
      Configure your production Swoosh adapter and credentials in runtime.exs before deployment.
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
