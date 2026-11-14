Code.require_file("../../../support/generator_article.exs", __DIR__)

defmodule Mix.Brando.Igniter.ResourceRenderMultiSiteTest do
  # Compiles the router scope and public pages brando.gen --public-route plans
  # on a multi-site installation without the CMS site, and requests them on
  # two sites. Acme's default language is Norwegian, Beta's English; the
  # installation's is English (config/test.exs). Not async: it defines
  # modules and sites.
  use Brando.ConnCase, async: false

  alias Brando.IgniterCase
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias GeneratorStudio.Catalog.Article

  @web "lib/generator_studio_multi_web"

  setup_all do
    result =
      IgniterCase.phoenix_project(
        app: :generator_studio,
        module: "GeneratorStudio",
        web: "GeneratorStudioMultiWeb",
        files: %{
          "config/brando.exs" => """
          import Config

          config :brando,
            default_language: "en",
            languages: [[value: "en", text: "English"], [value: "no", text: "Norsk"]],
            scope_default_language_routes: false,
            tenancy_mode: :multi
          """,
          "lib/generator_studio_multi_web.ex" => """
          defmodule GeneratorStudioMultiWeb do
            def router do
              quote do
                use Phoenix.Router, helpers: false
                import Plug.Conn
                import Phoenix.Controller
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
          "#{@web}/router.ex" => """
          defmodule GeneratorStudioMultiWeb.Router do
            use GeneratorStudioMultiWeb, :router
            import Brando.Router

            pipeline :browser do
              plug :accepts, ["html"]
            end

            admin_routes "/admin" do
              live "/", GeneratorStudioAdmin.DashboardLive
            end
          end
          """,
          "lib/generator_studio/catalog/article.ex" => "defmodule GeneratorStudio.Catalog.Article do\nend\n"
        }
      )
      |> Igniter.compose_task(Mix.Tasks.Brando.Gen, ["GeneratorStudio.Catalog.Article", "--public-route", "/articles"])

    [] = result.issues

    dir = Path.join(System.tmp_dir!(), "brando-resource-render-multi-#{System.unique_integer([:positive])}")

    files =
      for path <- [
            "lib/generator_studio_multi_web.ex",
            "#{@web}/router.ex",
            "#{@web}/catalog/article_controller.ex",
            "#{@web}/catalog/article_html.ex"
          ] do
        file = Path.join(dir, path)
        File.mkdir_p!(Path.dirname(file))
        File.write!(file, IgniterCase.source(result, path))
        file
      end

    # The generated context queries a table these tests do not have.
    context = Path.join(dir, "catalog.ex")

    File.write!(context, """
    defmodule GeneratorStudio.Catalog do
      def list_articles(%{status: :published, language: language}),
        do: {:ok, Enum.filter(#{inspect(__MODULE__)}.articles(), &(&1.language == language))}

      def get_article(%{matches: %{slug: slug}, language: language, status: :published, preload: _preload}) do
        case Enum.find(#{inspect(__MODULE__)}.articles(), &(&1.slug == slug and &1.language == language)) do
          nil -> {:error, {:article, :not_found}}
          article -> {:ok, article}
        end
      end
    end
    """)

    # Printed warnings are checked below instead.
    {{:ok, modules, %{compile_warnings: compile_warnings, runtime_warnings: runtime_warnings}}, _output} =
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        Kernel.ParallelCompiler.compile([context | files], return_diagnostics: true)
      end)

    # The router names admin views these tests do not compile.
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

  setup do
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(nil)
    Cache.clear()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
    end)

    site("Acme", "acme", ["en", "no"], "no", "acme.test")
    site("Beta", "beta", ["en"], "en", "beta.test")
    Cache.warm()
    :ok
  end

  defp site(name, key, languages, default_language, domain) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: languages,
        default_language: default_language,
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _} =
      Registry.create_environment(site, %{name: "Production", key: "production", live: true, domain: domain},
        actor: :system
      )
  end

  # An English and a Norwegian entry share a slug, as translations may.
  def articles do
    [
      %Article{id: 1, title: "Hello", slug: "hei", status: :published, language: "en", rendered_blocks: ""},
      %Article{id: 2, title: "Hei", slug: "hei", status: :published, language: "no", rendered_blocks: ""}
    ]
  end

  # Through the generated router, as a request to the site's host.
  defp request(host, path) do
    router = Module.concat(GeneratorStudioMultiWeb, Router)
    conn = %{build_conn(:get, path) | host: host}
    router.call(conn, router.init([]))
  end

  test "the unprefixed routes show the site's default language, and each prefix its own" do
    for {host, path, title, back} <- [
          {"acme.test", "/articles/hei", "Hei", "/articles"},
          {"acme.test", "/en/articles/hei", "Hello", "/en/articles"},
          {"acme.test", "/no/articles/hei", "Hei", "/no/articles"},
          {"beta.test", "/articles/hei", "Hello", "/articles"}
        ] do
      conn = request(host, path)
      assert conn.status == 200, "#{host}#{path}"
      assert conn.resp_body =~ "<h1>#{title}</h1>", "#{host}#{path}"
      assert conn.resp_body =~ ~s(<a href="#{back}">Back to articles</a>), "#{host}#{path}"
    end

    index = request("acme.test", "/articles")
    assert index.resp_body =~ ~s(href="/articles/hei">Hei</a>)
    refute index.resp_body =~ "Hello"

    index = request("acme.test", "/en/articles")
    assert index.resp_body =~ ~s(href="/en/articles/hei">Hello</a>)
  end
end
