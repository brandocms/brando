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
    assert Keyword.has_key?(modules, GeneratorStudio.Catalog)
    assert apply(GeneratorStudio.Catalog, :custom, []) == :preserved
    assert function_exported?(GeneratorStudio.Catalog, :list_products, 1)
    assert function_exported?(GeneratorStudio.Catalog, :get_category, 1)
    assert function_exported?(GeneratorStudio.Catalog, :create_category, 2)

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
end
