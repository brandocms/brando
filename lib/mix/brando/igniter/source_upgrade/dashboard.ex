if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.Dashboard do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # The admin's start page is the application's `<App>Admin.DashboardLive`.
    # The installer before 0.55 wrote one that renders only
    # `<Content.header title="Dashboard" …/>`, so the dashboard showed a
    # header and nothing else. A module that is exactly that, apart from its
    # Gettext import, gets the installer's current template, which renders
    # Brando's dashboard component. Any other DashboardLive is listed.

    alias Mix.Brando.Igniter.Template
    alias Rewrite.Source

    @old_render ~s(<Content.header title="Dashboard" subtitle={@current_user.name} />)
    @definition ~r/^\s*defmodule\s+([A-Z][\w.]*)Admin\.DashboardLive\s+do\b/m

    @doc "Replaces an unedited pre-0.55 installer `DashboardLive`, or lists one that only renders a header."
    def replace_installer_dashboard(igniter) do
      igniter = Igniter.include_glob(igniter, "lib/**/*.ex")

      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.map(&{Source.get(&1, :path), Source.get(&1, :content)})
      |> Enum.filter(fn {path, content} -> String.starts_with?(path, "lib/") and content =~ @definition end)
      |> Enum.sort()
      |> Enum.reduce(igniter, fn {path, content}, igniter ->
        [_, application] = Regex.run(@definition, content)

        cond do
          installer_dashboard?(content, application) -> replace(igniter, path, application)
          content =~ "Content.header" and not (content =~ "Components.Dashboard") -> header_only(igniter, path)
          true -> igniter
        end
      end)
    end

    # The old installer's module: the Listing `use`, the Content alias, an
    # optional Gettext import, and a render of the header alone.
    defp installer_dashboard?(content, application) do
      with {:ok, {:defmodule, _, [_name, [{_do, body}]]}} <- Sourceror.parse_string(content),
           statements = statements(body),
           [render] <- for({:def, _, [{:render, _, _} | _]} = render <- statements, do: render),
           true <- Enum.all?(statements -- [render], &installer_statement?(&1, application)) do
        render_template(render) == @old_render
      else
        _ -> false
      end
    end

    defp statements({:__block__, _, statements}) when is_list(statements), do: statements
    defp statements(statement), do: [statement]

    defp installer_statement?(statement, application) do
      code = Sourceror.to_string(statement)

      code in [
        "use BrandoAdmin.LiveView.Listing, schema: nil",
        "alias BrandoAdmin.Components.Content",
        "import #{application}Admin.Gettext",
        "use Gettext, backend: #{application}Admin.Gettext"
      ]
    end

    defp render_template({:def, _, [{:render, _, [{:assigns, _, context}]}, [{_do, body}]]}) when is_atom(context) do
      case body do
        {:sigil_H, _, [{:<<>>, _, [template]}, _modifiers]} when is_binary(template) -> String.trim(template)
        _ -> nil
      end
    end

    defp render_template(_render), do: nil

    defp replace(igniter, path, application) do
      binding = [application_module: application]

      case Template.render(igniter, "brando.install", "lib/application_name_admin/live/dashboard_live.ex", binding) do
        {:ok, igniter, contents} ->
          igniter
          |> Igniter.update_file(path, &Source.update(&1, :content, contents))
          # With the application's formatter and its plugins: the template's
          # one-line `~H` is wider than any line length.
          |> Igniter.format([path])
          |> Igniter.add_notice("""
          #{path} was the old installer's DashboardLive, which renders only a
          header. The task replaced it with the installer's current one, which
          renders Brando's dashboard.
          """)

        {:error, message} ->
          Igniter.add_issue(igniter, message)
      end
    end

    defp header_only(igniter, path) do
      Igniter.add_warning(igniter, """
      #{path} renders `Content.header` and not Brando's dashboard component, so
      the admin's start page shows a header only. The task did not replace it
      because it differs from the old installer's. Render
      `BrandoAdmin.Components.Dashboard` in it as the installer's template does
      (guides/migrating_from_053.md has the code).
      """)
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.Dashboard do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
