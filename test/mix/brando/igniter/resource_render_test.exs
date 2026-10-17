defmodule GeneratorStudio.Catalog.Note do
  use Brando.Blueprint,
    application: "GeneratorStudio",
    domain: "Catalog",
    schema: "Note",
    singular: "note",
    plural: "notes"

  attributes do
    attribute :title, :string, required: true
  end
end

defmodule Mix.Brando.Igniter.ResourceRenderTest do
  # Compiles the public pages brando.gen --public-route plans, with and without
  # the CMS site, and calls them as the application would. Not async: it
  # defines modules.
  use Brando.ConnCase, async: false

  alias Brando.IgniterCase
  alias GeneratorStudio.Catalog.Article

  @web "lib/generator_studio_web"

  setup_all do
    base =
      IgniterCase.phoenix_project(
        app: :generator_studio,
        module: "GeneratorStudio",
        files: %{
          "lib/generator_studio_web.ex" => """
          defmodule GeneratorStudioWeb do
            def router do
              quote do
                use Phoenix.Router, helpers: false
                import Phoenix.LiveView.Router
              end
            end

            def controller do
              quote do
                use Phoenix.Controller, formats: [:html]
                import Plug.Conn
              end
            end

            def html, do: quote(do: use(Phoenix.Component))

            defmacro __using__(which), do: apply(__MODULE__, which, [])
          end
          """,
          "lib/generator_studio/catalog/article.ex" => "defmodule GeneratorStudio.Catalog.Article do\nend\n",
          "lib/generator_studio/catalog/note.ex" => "defmodule GeneratorStudio.Catalog.Note do\nend\n"
        }
      )

    installed = base |> Igniter.compose_task(Mix.Tasks.Brando.Install, []) |> IgniterCase.apply_and_reload()

    plain =
      Igniter.compose_task(installed, Mix.Tasks.Brando.Gen, ["GeneratorStudio.Catalog.Note", "--public-route", "/notes"])

    site =
      installed
      |> Igniter.compose_task(Mix.Tasks.Brando.Gen.Site, [])
      |> IgniterCase.apply_and_reload()
      |> Igniter.compose_task(Mix.Tasks.Brando.Gen, ["GeneratorStudio.Catalog.Article", "--public-route", "/articles"])

    [] = plain.issues
    [] = site.issues

    dir = Path.join(System.tmp_dir!(), "brando-resource-render-#{System.unique_integer([:positive])}")

    files =
      for {igniter, paths} <- [
            {plain,
             ["lib/generator_studio_web.ex", "#{@web}/catalog/note_controller.ex", "#{@web}/catalog/note_html.ex"]},
            {site,
             [
               "#{@web}/router.ex",
               "#{@web}/cms/layouts.ex",
               "#{@web}/cms/site_context.ex",
               "#{@web}/catalog/article_controller.ex",
               "#{@web}/catalog/article_html.ex"
             ]}
          ],
          path <- paths do
        file = Path.join(dir, path)
        File.mkdir_p!(Path.dirname(file))
        File.write!(file, IgniterCase.source(igniter, path))
        file
      end

    # The generated context queries tables these tests do not have.
    context = Path.join(dir, "catalog.ex")

    File.write!(context, """
    defmodule GeneratorStudio.Catalog do
      def list_articles(%{status: :published, filter: %{language: "en"}}), do: {:ok, [#{inspect(__MODULE__)}.article()]}

      def get_article(%{
            matches: %{slug: "known", language: "en"},
            status: :published,
            preload: [:alternate_entries]
          }),
        do: {:ok, #{inspect(__MODULE__)}.article()}

      def get_article(%{matches: %{slug: slug}}) when is_binary(slug), do: {:error, {:article, :not_found}}

      def list_notes(%{}), do: {:ok, [%GeneratorStudio.Catalog.Note{id: 1, title: "First note"}]}
      def get_note(%{matches: %{id: 1}}), do: {:ok, %GeneratorStudio.Catalog.Note{id: 1, title: "First note"}}
      def get_note(%{matches: %{id: id}}) when is_integer(id), do: {:error, {:note, :not_found}}
    end
    """)

    # Printed warnings are checked below instead.
    {{:ok, modules, %{compile_warnings: compile_warnings, runtime_warnings: runtime_warnings}}, _output} =
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        Kernel.ParallelCompiler.compile([context | files], return_diagnostics: true)
      end)

    # The application compiles with --warnings-as-errors. The router names
    # modules (admin views, CMS controllers) these tests do not compile.
    [] =
      Enum.reject(
        compile_warnings ++ runtime_warnings,
        &(String.ends_with?(&1.file, "router.ex") and &1.message =~ "is not available or is yet to be defined")
      )

    on_exit(fn ->
      File.rm_rf!(dir)

      for module <- modules do
        :code.purge(module)
        :code.delete(module)
      end
    end)

    :ok
  end

  def article do
    %Article{
      id: 1,
      title: "Known article",
      slug: "known",
      status: :published,
      language: :en,
      alternate_entries: [],
      rendered_blocks: "<p>Rendered blocks</p>",
      rendered_bio_blocks: "<p>Rendered bio</p>"
    }
  end

  # Compiled in setup_all, so not named literally: the compiler would warn.
  defp call(controller, conn, action, params) do
    conn = conn |> Plug.Conn.assign(:language, "en") |> Phoenix.Controller.put_format("html")
    Module.concat([GeneratorStudioWeb, Catalog, controller]).call(%{conn | params: params}, action)
  end

  test "with the CMS site, the routes go through :brando_site ahead of the CMS catch-all" do
    router = Module.concat(GeneratorStudioWeb, Router)

    for {path, action, params} <- [{"/articles", :index, %{}}, {"/articles/known", :show, %{"slug" => "known"}}] do
      assert %{pipe_through: [:browser, :brando_site], plug: plug, plug_opts: ^action, path_params: ^params} =
               Phoenix.Router.route_info(router, "GET", path, "")

      assert plug == Module.concat(GeneratorStudioWeb, Catalog.ArticleController)
    end
  end

  test "an entry renders its title and blocks inside the site's layout, with Brando meta", %{conn: conn} do
    conn = call(ArticleController, conn, :show, %{"slug" => "known"})
    assert conn.status == 200
    assert conn.resp_body =~ ~s(<html lang="en">)
    assert conn.resp_body =~ ~s(id="top")
    assert conn.resp_body =~ "<h1>Known article</h1>"
    assert conn.resp_body =~ "<p>Rendered blocks</p>"
    assert conn.resp_body =~ "<p>Rendered bio</p>"
    assert conn.assigns.page_title == "Known article"
    assert Brando.Plug.HTML.get_page_entry(conn) == article()

    index = call(ArticleController, build_conn(), :index, %{})
    assert index.status == 200
    assert index.resp_body =~ ~s(href="/articles/known")
    assert index.resp_body =~ ~s(<html lang="en">)
  end

  test "a missing entry is left to Brando's fallback controller, which renders the site's 404" do
    controller = Module.concat(GeneratorStudioWeb, Catalog.ArticleController)
    conn = build_conn() |> Plug.Conn.assign(:language, "en") |> Phoenix.Controller.put_format("html")
    assert controller.show(conn, %{"slug" => "missing"}) == {:error, {:article, :not_found}}
  end

  test "without the CMS site, an entry shows by id and a missing or malformed id is a 404", %{conn: conn} do
    shown = call(NoteController, conn, :show, %{"id" => "1"})
    assert shown.status == 200
    assert shown.resp_body =~ "<h1>First note</h1>"

    for id <- ["2", "abc", "1.5", "-1", "99999999999999999999999"] do
      error = assert_raise Plug.Conn.WrapperError, fn -> call(NoteController, build_conn(), :show, %{"id" => id}) end
      assert %Ecto.NoResultsError{} = error.reason
      assert Plug.Exception.status(error.reason) == 404
    end
  end
end
