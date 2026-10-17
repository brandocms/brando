defmodule GeneratorStudio.Catalog.Product do
  use Brando.Blueprint,
    application: "GeneratorStudio",
    domain: "Catalog",
    schema: "Product",
    singular: "product",
    plural: "products"

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug
  end
end

defmodule GeneratorStudio.Catalog.OtherProduct do
  use Brando.Blueprint,
    application: "GeneratorStudio",
    domain: "Catalog",
    schema: "OtherProduct",
    singular: "product",
    plural: "products"

  attributes do
    attribute :title, :string
  end
end

defmodule GeneratorStudio.Catalog.Category do
  use Brando.Blueprint,
    application: "GeneratorStudio",
    domain: "Catalog",
    schema: "Category",
    singular: "category",
    plural: "categories"

  attributes do
    attribute :name, :string, required: true
  end
end

defmodule GeneratorStudio.Catalog.Tag do
  use Brando.Blueprint,
    application: "GeneratorStudio",
    domain: "Catalog",
    schema: "Tag",
    singular: "tag",
    plural: "tags"

  primary_key {:id, :binary_id, autogenerate: true}

  attributes do
    attribute :name, :string
  end
end

defmodule GeneratorStudio.Catalog.Reading do
  use Brando.Blueprint,
    application: "GeneratorStudio",
    domain: "Catalog",
    schema: "Reading",
    singular: "reading",
    plural: "readings"

  primary_key false

  attributes do
    attribute :name, :string
  end
end

defmodule Mix.Tasks.Brando.Gen.Test do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase

  defp project(files \\ %{}) do
    IgniterCase.phoenix_project(
      module: "GeneratorStudio",
      files:
        Map.merge(
          %{
            "lib/generator_studio/catalog/product.ex" => "defmodule GeneratorStudio.Catalog.Product do\nend\n",
            "lib/generator_studio/catalog/category.ex" => "defmodule GeneratorStudio.Catalog.Category do\nend\n",
            "lib/generator_studio/catalog/article.ex" => "defmodule GeneratorStudio.Catalog.Article do\nend\n",
            "lib/generator_studio/catalog/tag.ex" => "defmodule GeneratorStudio.Catalog.Tag do\nend\n",
            "lib/generator_studio/catalog/reading.ex" => "defmodule GeneratorStudio.Catalog.Reading do\nend\n",
            "lib/generator_studio_web/router.ex" => """
            defmodule GeneratorStudioWeb.Router do
              use GeneratorStudioWeb, :router
              import Brando.Router
              admin_routes "/admin" do
                live "/", GeneratorStudioAdmin.DashboardLive
              end
            end
            """
          },
          files
        )
    )
  end

  defp generate(igniter, module \\ "GeneratorStudio.Catalog.Product", options \\ []) do
    Igniter.compose_task(igniter, Mix.Tasks.Brando.Gen, [module | options])
  end

  test "generates and compiles two resources in a shared context while preserving custom code" do
    base =
      project(%{
        "lib/generator_studio/catalog.ex" => """
        defmodule GeneratorStudio.Catalog do
          # Keep this application-specific function.
          def custom, do: :preserved
        end
        """
      })

    result = base |> generate() |> generate("GeneratorStudio.Catalog.Category")
    assert result.issues == []
    source = IgniterCase.source(result, "lib/generator_studio/catalog.ex")
    assert source =~ "def custom"
    assert source =~ "Keep this application-specific function"
    assert length(Regex.scan(~r/use Brando.Query/, source)) == 1
    modules = Code.compile_string(source)
    assert {catalog, _binary} = List.keyfind(modules, GeneratorStudio.Catalog, 0)
    assert catalog.custom() == :preserved
    assert function_exported?(GeneratorStudio.Catalog, :list_products, 1)
    assert function_exported?(GeneratorStudio.Catalog, :get_category, 1)
    assert function_exported?(GeneratorStudio.Catalog, :create_category, 2)
    assert function_exported?(GeneratorStudio.Catalog, :duplicate_product, 2)
    assert function_exported?(GeneratorStudio.Catalog, :duplicate_category, 2)
    assert source =~ ~r/mutation[ (]:duplicate, \{GeneratorStudio.Catalog.Product, change_fields: \[:title, :slug\]\}/
    assert source =~ ~r/mutation[ (]:duplicate, \{GeneratorStudio.Catalog.Category, change_fields: \[:name\]\}/

    # Running it again finds the declarations, `{Schema, opts}` form included.
    rerun = result |> generate() |> generate("GeneratorStudio.Catalog.Category")
    assert rerun.issues == []
    rerun_source = IgniterCase.source(rerun, "lib/generator_studio/catalog.ex")
    assert length(Regex.scan(~r/mutation[ (]:duplicate/, rerun_source)) == 2

    on_exit(fn ->
      :code.purge(GeneratorStudio.Catalog)
      :code.delete(GeneratorStudio.Catalog)
    end)

    router = IgniterCase.source(result, "lib/generator_studio_web/router.ex")
    assert router =~ "/catalog/products/update/:entry_id"
    assert router =~ "CategoryListLive"
    refute Igniter.exists?(result, "lib/generator_studio_web/catalog/product_controller.ex")
    assert result.tasks == []
  end

  test "public output is explicit and uses consumer namespaces without assumed image fields" do
    result =
      generate(project(), "GeneratorStudio.Catalog.Product", [
        "--public-route",
        "/products",
        "--admin-module",
        "Backoffice"
      ])

    assert result.issues == []

    assert IgniterCase.source(result, "lib/backoffice/catalog/product_form_live.ex") =~
             "defmodule Backoffice.Catalog.ProductFormLive"

    html = IgniterCase.source(result, "lib/generator_studio_web/catalog/product_html.ex")
    assert html =~ "entry.title"
    refute html =~ "entry.cover"

    assert IgniterCase.source(result, "lib/generator_studio_web/router.ex") =~
             ~s("/products", GeneratorStudioWeb.Catalog.ProductController)
  end

  test "reruns preserve existing queries and do not duplicate routes" do
    first = project() |> generate() |> Igniter.Test.apply_igniter!()
    loaded = Enum.reduce(Map.keys(first.assigns.test_files), first, &Igniter.include_existing_file(&2, &1))
    result = generate(loaded)
    assert result.issues == []
    Igniter.Test.assert_unchanged(result)
  end

  test "custom context function and owned-file collisions block overwrite" do
    for files <- [
          %{
            "lib/generator_studio/catalog.ex" =>
              "defmodule GeneratorStudio.Catalog do\n def list_products(opts), do: opts\nend"
          },
          %{
            "lib/generator_studio_admin/catalog/product_form_live.ex" =>
              "defmodule GeneratorStudioAdmin.Catalog.ProductFormLive do\n def custom, do: true\nend"
          }
        ] do
      result = generate(project(files), "GeneratorStudio.Catalog.Product", ["--yes"])
      assert result.issues != []

      for path <- Map.keys(files) do
        if path == "lib/generator_studio/catalog.ex" do
          assert IgniterCase.source(result, path) =~ "def list_products(opts), do: opts"
        else
          Igniter.Test.assert_unchanged(result, path)
        end
      end
    end
  end

  test "invalid modules, fields and public routes fail with no source writes" do
    for {module, options} <- [
          {"Unknown.Catalog.Product", []},
          {"String", []},
          {"Brando.MigrationTest.Property", []},
          {"../Bad", []},
          {"GeneratorStudio.Catalog.Product", ["--main-field", "missing"]},
          {"GeneratorStudio.Catalog.Product", ["--public-route", "/admin"]}
        ] do
      result = generate(project(), module, options)
      assert result.issues != []
      Igniter.Test.assert_unchanged(result)
      refute_received {:mix_shell, :prompt, _}
    end
  end

  test "Blueprint declarations cannot silently generate overlapping context functions" do
    for declaration <- ["query :list, OtherProduct", "mutation :create, OtherProduct"] do
      result =
        project(%{
          "lib/generator_studio/catalog.ex" => """
          defmodule GeneratorStudio.Catalog do
            use Brando.Query
            alias GeneratorStudio.Catalog.OtherProduct
            #{declaration}
          end
          """
        })
        |> generate()

      assert Enum.any?(result.issues, &String.contains?(&1, "another Blueprint declaration"))
      source = IgniterCase.source(result, "lib/generator_studio/catalog.ex")
      assert source =~ "OtherProduct"
      assert source =~ "alias GeneratorStudio.Catalog.OtherProduct"
    end
  end

  test "pending Blueprint changes must be accepted and compiled first" do
    result =
      project()
      |> Igniter.update_elixir_file("lib/generator_studio/catalog/product.ex", fn zipper ->
        {:ok,
         Igniter.Code.Common.replace_code(
           zipper,
           "defmodule GeneratorStudio.Catalog.Product do\n def pending, do: true\nend"
         )}
      end)
      |> generate()

    assert Enum.any?(result.issues, &String.contains?(&1, "pending source changes"))
    refute Igniter.exists?(result, "lib/generator_studio/catalog.ex")
  end

  test "nested existing public routes block conflicting generation" do
    base = project()

    base =
      Igniter.update_elixir_file(base, "lib/generator_studio_web/router.ex", fn zipper ->
        {:ok, module} = Igniter.Code.Common.move_to_do_block(zipper)

        {:ok,
         Igniter.Code.Common.add_code(module, """
         scope "/products", GeneratorStudioWeb do
           get "/", ExistingController, :index
         end
         """)}
      end)

    result = generate(base, "GeneratorStudio.Catalog.Product", ["--public-route", "/products"])
    assert Enum.any?(result.issues, &String.contains?(&1, "Public routes at /products conflict"))
  end

  test "route ownership includes resources and parameter names but respects scope prefixes" do
    for {routes, conflict?} <- [
          {~s(resources "/products", ExistingController), true},
          {~s(get "/:section", ExistingController, :index), true},
          {~s(get "/:section/:id", ExistingController, :show), true},
          {~s(get "/products/new", ExistingController, :new), true},
          {~s(resources "/:collection", ExistingController), true},
          {~s(forward "/", ExistingPlug), true},
          {~s(get "/:section", GeneratorStudioWeb.Catalog.ProductController, :index\nget "/:section/:id", GeneratorStudioWeb.Catalog.ProductController, :show),
           true},
          {~s(get "/products/:slug", ExistingController, :show), true},
          {~s(scope "/api" do\n get "/products", ExistingController, :index\nend), false},
          {~s(post "/products", ExistingController, :create), false},
          {~s(get "/*path", ExistingController, :show), false}
        ] do
      base =
        project()
        |> Igniter.update_elixir_file("lib/generator_studio_web/router.ex", fn zipper ->
          {:ok, module} = Igniter.Code.Common.move_to_do_block(zipper)
          {:ok, Igniter.Code.Common.add_code(module, routes, placement: :before)}
        end)

      result = generate(base, "GeneratorStudio.Catalog.Product", ["--public-route", "/products"])
      assert result.issues != [] == conflict?, inspect(result.issues)

      unless conflict? do
        rerun =
          result
          |> IgniterCase.apply_and_reload()
          |> generate("GeneratorStudio.Catalog.Product", ["--public-route", "/products"])

        assert rerun.issues == []
        Igniter.Test.assert_unchanged(rerun)
      end
    end
  end

  defp notices(result), do: Enum.join(result.notices, "\n")

  # Source on one line, for calls the formatter breaks over several.
  defp flat(result, path), do: result |> IgniterCase.source(path) |> String.replace(~r/[\s(]+/, " ")

  # The fixture's formatter keeps the parentheses on router calls.
  defp router(result),
    do: result |> IgniterCase.source("lib/generator_studio_web/router.ex") |> String.replace(["(", ")"], " ")

  @languages """
  import Config

  config :brando,
    default_language: "en",
    languages: [[value: "en", text: "English"], [value: "no", text: "Norsk"]],
    scope_default_language_routes: false
  """

  # The routes, layout and error pages mix brando.gen.site plans, for a site
  # in English and Norwegian.
  defp site_project(files \\ %{}) do
    %{"config/brando.exs" => @languages}
    |> Map.merge(files)
    |> project()
    |> Igniter.compose_task(Mix.Tasks.Brando.Gen.Site, ["--yes"])
    |> IgniterCase.apply_and_reload()
  end

  test "the notice names --public-route only when it was not given" do
    assert notices(generate(project())) =~ "generated only with --public-route"

    result = generate(project(), "GeneratorStudio.Catalog.Product", ["--public-route", "/products"])
    assert result.issues == []
    refute notices(result) =~ "--public-route"
  end

  test "without the CMS site, public pages show by slug, raise a 404 and say what to wire by hand" do
    result = generate(project(), "GeneratorStudio.Catalog.Product", ["--public-route", "/products"])
    assert result.issues == []

    router = router(result)
    assert router =~ ~s(get "/products/:slug", GeneratorStudioWeb.Catalog.ProductController, :show)
    assert router =~ ~r/scope "\/" do\s+pipe_through :browser\s+get "\/products"/

    controller = IgniterCase.source(result, "lib/generator_studio_web/catalog/product_controller.ex")
    assert controller =~ "use GeneratorStudioWeb, :controller"
    assert controller =~ "Brando.Plug.Tenant"
    assert controller =~ ~s(def show(conn, %{"slug" => slug}\))
    assert controller =~ "matches: %{slug: slug}"
    assert controller =~ "raise Ecto.NoResultsError, queryable: GeneratorStudio.Catalog.Product"
    refute controller =~ "send_resp"

    html = IgniterCase.source(result, "lib/generator_studio_web/catalog/product_html.ex")
    assert html =~ ~S(href={"/products/#{entry.slug}"})
    refute html =~ "render_blocks"

    notices = notices(result)
    assert notices =~ "pipes through :browser only"
    assert notices =~ "Brando.Plug.Lockdown"
    assert notices =~ "mix brando.gen.site"
    # The fixture Blueprint has no absolute_url, which is absolute_url false.
    assert notices =~ ~s(absolute_url ~H"/products/{@entry.slug}")
  end

  test "a Blueprint without a slug shows by id, and a malformed id is a missing entry" do
    result = generate(project(), "GeneratorStudio.Catalog.Category", ["--public-route", "/categories"])
    assert result.issues == []

    assert router(result) =~ ~s(get "/categories/:id", GeneratorStudioWeb.Catalog.CategoryController, :show)

    controller = IgniterCase.source(result, "lib/generator_studio_web/catalog/category_controller.ex")
    assert controller =~ ~s(def show(conn, %{"id" => id}\))
    assert controller =~ "{:ok, id} <- parse_id(id)"
    assert controller =~ "Integer.parse(id)"
    assert controller =~ "{:error, {:category, :not_found}}"
    assert notices(result) =~ ~s(absolute_url ~H"/categories/{@entry.id}")
  end

  test "with the CMS site, public pages pipe through :brando_site and render in the site's layout" do
    result = generate(site_project(), "GeneratorStudio.Catalog.Article", ["--public-route", "/articles"])
    assert result.issues == []

    router = router(result)
    assert router =~ ~r/scope "\/" do\s+pipe_through \[:browser, :brando_site\]\s+get "\/articles"/
    assert router =~ ~s(get "/articles/:slug", GeneratorStudioWeb.Catalog.ArticleController, :show)

    # After the pipeline it uses, before the CMS catch-all.
    [{pipeline, _}] = Regex.run(~r/pipeline :brando_site/, router, return: :index)
    [{public, _}] = Regex.run(~r/get "\/articles"/, router, return: :index)
    [{catch_all, _}] = Regex.run(~r/get "\/\*path"/, router, return: :index)
    assert pipeline < public and public < catch_all

    # Norwegian pages are under /no, as the CMS pages are; :brando_site gives the language.
    assert router =~
             ~r/scope "\/no", as: :no\s+do\s+get "\/articles", GeneratorStudioWeb.Catalog.ArticleController, :index/

    assert router =~ ~r/get "\/articles\/:slug", GeneratorStudioWeb.Catalog.ArticleController, :show\s+end\s+end/
    refute router =~ "assigns:"

    controller = IgniterCase.source(result, "lib/generator_studio_web/catalog/article_controller.ex")
    assert controller =~ "use BrandoWeb, :controller"
    assert controller =~ ~r/plug\(?:put_root_layout, html: \{GeneratorStudioWeb.CMS.Layouts, :root\}/
    assert controller =~ ~r/action_fallback\(?BrandoWeb.FallbackController/
    assert controller =~ "put_meta(GeneratorStudio.Catalog.Article, entry)"
    # Translations may share a slug: the query engine's language option picks the request's.
    flat = flat(result, "lib/generator_studio_web/catalog/article_controller.ex")

    assert flat =~
             "%{ matches: %{slug: slug}, language: conn.assigns.language, status: :published, preload: [:alternate_entries, :meta_image, :cover] })"

    assert flat =~ "list_articles %{ status: :published, language: conn.assigns.language })"

    assert flat =~
             ~S'defp base_path %{path_info: [language | _], assigns: %{language: language}}), do: "/#{language}/articles"'

    # No clauses of its own for the language.
    context = IgniterCase.source(result, "lib/generator_studio/catalog.ex")
    refute context =~ "q.language"

    on_exit(fn ->
      :code.purge(GeneratorStudio.Catalog)
      :code.delete(GeneratorStudio.Catalog)
    end)

    assert {GeneratorStudio.Catalog, _} = context |> Code.compile_string() |> List.keyfind(GeneratorStudio.Catalog, 0)
    assert controller =~ "put_hreflang(entry)"
    # Tenant comes from the :brando_site pipeline.
    refute controller =~ "Brando.Plug.Tenant"

    html = IgniterCase.source(result, "lib/generator_studio_web/catalog/article_html.ex")
    assert html =~ "use BrandoWeb, :html"
    assert html =~ "<Brando.HTML.render_blocks entry={@entry} />"
    assert html =~ "<Brando.HTML.render_blocks entry={@entry} field={:bio_blocks} />"

    assert html =~ ~S(href={"#{@base_path}/#{entry.slug}"})
    assert html =~ "<.link href={@base_path}>Back to articles</.link>"

    notices = notices(result)
    assert notices =~ "GeneratorStudioWeb.CMS.Layouts"
    assert notices =~ "/articles for en, /no/articles for no"
    # Its absolute_url gives one path for every language.
    assert notices =~ "absolute_url ~H|{route_i18n(@entry, :article_path, :show, [@entry.slug])}|"

    rerun =
      result
      |> IgniterCase.apply_and_reload()
      |> generate("GeneratorStudio.Catalog.Article", ["--public-route", "/articles"])

    assert rerun.issues == []
    Igniter.Test.assert_unchanged(rerun)
  end

  test "a UUID primary key is cast as one, and a Blueprint without an :id has no pages by id" do
    result = generate(project(), "GeneratorStudio.Catalog.Tag", ["--public-route", "/tags"])
    assert result.issues == []
    controller = IgniterCase.source(result, "lib/generator_studio_web/catalog/tag_controller.ex")
    assert controller =~ "Ecto.UUID.cast(id)"
    refute controller =~ "Integer.parse"

    result = generate(project(), "GeneratorStudio.Catalog.Reading", ["--public-route", "/readings"])
    assert [issue] = result.issues
    assert issue =~ "GeneratorStudio.Catalog.Reading's public pages look entries up by id, but its primary key is []"
  end

  test "without the CMS site, a translatable Blueprint's routes give each language in their assigns" do
    result =
      %{"config/brando.exs" => @languages}
      |> project()
      |> generate("GeneratorStudio.Catalog.Article", ["--public-route", "/articles"])

    assert result.issues == []

    router = router(result)
    assert router =~ ~r/scope "\/", assigns: %\{language: "en"\}\s+do\s+pipe_through :browser\s+get "\/articles"/
    assert router =~ ~r/scope "\/no", as: :no, assigns: %\{language: "no"\}\s+do\s+get "\/articles"/

    controller = flat(result, "lib/generator_studio_web/catalog/article_controller.ex")
    assert controller =~ "list_articles %{ status: :published, language: conn.assigns.language })"
    assert controller =~ "matches: %{slug: slug}, language: conn.assigns.language"
  end

  test "a translatable Blueprint needs its languages in the config" do
    result = generate(project(), "GeneratorStudio.Catalog.Article", ["--public-route", "/articles"])
    assert [issue] = result.issues
    assert issue =~ "generated for each language in config :brando, :languages"
  end

  test "a consumer controller template from before slug routes keeps the :id route" do
    template = """
    defmodule <%= inspect controller_module %> do
      use <%= web_module %>, :controller

      def show(conn, %{"id" => id}) do
        {:ok, entry} = <%= inspect context_module %>.get_<%= singular %>(%{matches: %{id: id}})
        render(conn, :show, entry: entry)
      end
    end
    """

    result =
      %{"priv/templates/brando.gen/controller.ex" => template}
      |> project()
      |> generate("GeneratorStudio.Catalog.Product", ["--public-route", "/products"])

    assert result.issues == []
    assert router(result) =~ ~s(get "/products/:id", GeneratorStudioWeb.Catalog.ProductController, :show)

    controller = IgniterCase.source(result, "lib/generator_studio_web/catalog/product_controller.ex")
    assert controller =~ ~s(def show(conn, %{"id" => id}\))
    assert IgniterCase.source(result, "lib/generator_studio_web/catalog/product_html.ex") =~ ~S(entry.id)

    notices = notices(result)
    assert notices =~ "priv/templates/brando.gen/controller.ex overrides the default template"
    assert notices =~ ~s(absolute_url ~H"/products/{@entry.id}")
  end

  test "public pages need no language clauses in an existing context's filters and matches" do
    context = """
    defmodule GeneratorStudio.Catalog do
      use Brando.Query
      import Ecto.Query

      filters GeneratorStudio.Catalog.Article do
        fn {:title, value}, query -> from q in query, where: q.title == ^value end
      end

      matches GeneratorStudio.Catalog.Article do
        fn
          {:id, value}, query -> from q in query, where: q.id == ^value
          {:slug, value}, query -> from q in query, where: q.slug == ^value
        end
      end
    end
    """

    result =
      %{"config/brando.exs" => @languages, "lib/generator_studio/catalog.ex" => context}
      |> project()
      |> generate("GeneratorStudio.Catalog.Article", ["--public-route", "/articles"])

    assert result.issues == []
    refute IgniterCase.source(result, "lib/generator_studio/catalog.ex") =~ "language"

    # The query engine's own language: option, not a filter or match clause.
    controller = flat(result, "lib/generator_studio_web/catalog/article_controller.ex")
    assert controller =~ "matches: %{slug: slug}, language: conn.assigns.language"
    assert controller =~ "list_articles %{ status: :published, language: conn.assigns.language })"
    refute controller =~ "filter:"
  end
end
