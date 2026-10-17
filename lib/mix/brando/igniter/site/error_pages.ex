if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Site.ErrorPages do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Template
    alias Rewrite.Source

    @templates ["404.html.heex", "500.html.heex"]

    @doc """
    Gives the public site styled 404 and 500 pages in the site's layout.

    phx.new's `ErrorHTML`, which its `render_errors` configuration names, is
    replaced only while it is unchanged; its generated request test is replaced
    with it. A customized `ErrorHTML` or test is kept, with a notice.
    """
    def plan(igniter, project) do
      module = Module.concat(project.web_module, ErrorHTML)

      case ProjectModule.find_module(igniter, module) do
        {:ok, {igniter, source, _zipper}} ->
          path = Source.get(source, :path)
          current = Source.get(source, :content)
          {igniter, generated} = render(igniter, project, "error_html.ex")

          cond do
            generated == nil ->
              igniter

            same_code?(current, generated) ->
              templates(igniter, project, path)

            Enum.any?(phoenix_error_html(project), &same_code?(current, &1)) ->
              igniter
              |> Igniter.update_file(path, &Source.update(&1, :content, generated))
              |> templates(project, path)
              |> error_test(project)

            true ->
              Igniter.add_notice(igniter, """
              #{path} is customized, so the site's error pages were not generated.
              To use them, render the site's layout from #{inspect(module)}; see
              priv/templates/brando.gen.site/error_html.ex in Brando.
              """)
          end

        {:error, igniter} ->
          Igniter.add_notice(igniter, """
          There is no #{inspect(module)}, so the site's error pages were not generated.
          Point render_errors in config/config.exs at the module that renders your HTML errors.
          """)
      end
    end

    defp templates(igniter, project, path) do
      Enum.reduce(@templates, igniter, fn template, igniter ->
        case render(igniter, project, "error_html/#{template}") do
          {igniter, nil} -> igniter
          {igniter, contents} -> Files.create(igniter, Path.join([Path.dirname(path), "error_html", template]), contents)
        end
      end)
    end

    # phx.new's test asserts its plain-text pages.
    defp error_test(igniter, project) do
      path = "test/#{Macro.underscore(project.web_module)}/controllers/error_html_test.exs"

      if Igniter.exists?(igniter, path) do
        igniter = Igniter.include_existing_file(igniter, path)
        current = igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content)

        if Enum.any?(phoenix_error_test(project), &same_code?(current, &1)) do
          replace(igniter, project, path, "error_html_test.exs")
        else
          Igniter.add_notice(igniter, """
          #{path} was kept. If it asserts Phoenix's plain-text error pages,
          update it for the site's error pages.
          """)
        end
      else
        igniter
      end
    end

    defp replace(igniter, project, path, template) do
      case render(igniter, project, template) do
        {igniter, nil} -> igniter
        {igniter, contents} -> Igniter.update_file(igniter, path, &Source.update(&1, :content, contents))
      end
    end

    defp render(igniter, project, template) do
      case Template.render(igniter, "brando.gen.site", template, web_module: inspect(project.web_module)) do
        {:ok, igniter, contents} -> {igniter, contents}
        {:error, message} -> {Igniter.add_issue(igniter, message), nil}
      end
    end

    @doc "Whether two Elixir sources are the same code, comments, layout and formatting aside."
    def same_code?(left, right) do
      with {:ok, left} <- Sourceror.parse_string(left),
           {:ok, right} <- Sourceror.parse_string(right) do
        Sourceror.strip_meta(left) == Sourceror.strip_meta(right)
      else
        _ -> false
      end
    end

    # What phx.new 1.7 and 1.8 generate, without the comments; before 1.7.12
    # without the @moduledoc.
    defp phoenix_error_html(project) do
      web = inspect(project.web_module)

      body = """
        use #{web}, :html

        def render(template, _assigns) do
          Phoenix.Controller.status_message_from_template(template)
        end
      end
      """

      moduledoc = """
        @moduledoc \"\"\"
        This module is invoked by your endpoint in case of errors on HTML requests.

        See config/config.exs.
        \"\"\"
      """

      for doc <- [moduledoc, ""], do: "defmodule #{web}.ErrorHTML do\n" <> doc <> body
    end

    # 1.7 imports all of Phoenix.Template, 1.8 only render_to_string/4.
    defp phoenix_error_test(project) do
      web = inspect(project.web_module)

      for import <- ["import Phoenix.Template, only: [render_to_string: 4]", "import Phoenix.Template"] do
        """
        defmodule #{web}.ErrorHTMLTest do
          use #{web}.ConnCase, async: true

          #{import}

          test "renders 404.html" do
            assert render_to_string(#{web}.ErrorHTML, "404", "html", []) == "Not Found"
          end

          test "renders 500.html" do
            assert render_to_string(#{web}.ErrorHTML, "500", "html", []) == "Internal Server Error"
          end
        end
        """
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.Site.ErrorPages do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
