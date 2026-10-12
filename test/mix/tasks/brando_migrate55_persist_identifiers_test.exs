defmodule Mix.Tasks.Brando.Migrate55PersistIdentifiersTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate55

  @router_path "lib/lett_web/router.ex"

  # The Blueprint DSL and Phoenix routes without parentheses, as `import_deps`
  # gives an application.
  @formatter """
  [
    inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
    locals_without_parens: [
      live: 2, live: 3, trait: 1, identifier: 1, persist_identifier: 1, data_layer: 1, attribute: 3, absolute_url: 1
    ]
  ]
  """

  @router """
  defmodule LettWeb.Router do
    use BrandoWeb, :router

    import Brando.Router

    admin_routes do
      live "/", LettAdmin.DashboardLive

      scope "/menu", LettAdmin.Menu, as: :menu do
        live "/categories", CategoryListLive
        live "/categories/create", CategoryFormLive, :create
        live "/categories/update/:entry_id", CategoryFormLive, :update

        live "/menuitems", MenuitemListLive
        live "/menuitems/create", MenuitemFormLive, :create
        live "/menuitems/update/:entry_id", MenuitemFormLive, :update
      end

      live "/articles/categories", LettAdmin.Articles.CategoryListLive
      live "/articles/categories/create", LettAdmin.Articles.CategoryFormLive, :create
      live "/articles/categories/update/:entry_id", LettAdmin.Articles.CategoryFormLive, :update
    end
  end
  """

  @farm """
  defmodule Lett.Farms.Farm do
    @moduledoc \"\"\"
    Blueprint for Farm
    \"\"\"

    use Brando.Blueprint,
      application: "Lett",
      domain: "Farms",
      schema: "Farm",
      singular: "farm",
      plural: "farms"

    trait Brando.Trait.Creator
    trait Brando.Trait.Sequenced
    # trait Brando.Trait.Villain

    identifier "{{ entry.name }}"
    # absolute_url "{% route farm_path detail { entry.slug } %}"

    attributes do
      attribute :name, :string, required: true
    end
  end
  """

  test "sets persist_identifier false on Blueprints no admin route or LiveView edits" do
    igniter = migrate(files())

    assert source(igniter, "lib/lett/farms/farm.ex") =~ """
             # trait Brando.Trait.Villain

             identifier "{{ entry.name }}"
             persist_identifier false
             # absolute_url "{% route farm_path detail { entry.slug } %}"
           """

    assert_unchanged(igniter, [
      "lib/lett/menu/category.ex",
      "lib/lett/menu/menuitem.ex",
      "lib/lett/articles/category.ex",
      "lib/lett/prices/price.ex",
      "lib/lett/projects/inline_row.ex",
      "lib/lett/pages/landing.ex",
      "lib/lett/stores/store.ex"
    ])

    assert_has_notice(igniter, fn notice ->
      notice =~ "set `persist_identifier false`" and
        notice =~ "Lett.Farms.Farm (lib/lett/farms/farm.ex): no `admin_farm_form_path`" and
        not (notice =~ "Lett.Menu")
    end)

    # Routed in the `as: :menu` scope without `router_scope: :menu`, so its
    # helper is missing; it has a LiveView, so it is listed, not changed.
    assert_has_warning(igniter, fn warning ->
      warning =~ "Decide whether these Blueprints persist identifiers" and
        warning =~ "Lett.Menu.Menuitem (lib/lett/menu/menuitem.ex): has admin LiveViews but no `admin_menuitem_form_path`" and
        warning =~ "Lett.Stores.Store (lib/lett/stores/store.ex): has no admin editor, but has an `absolute_url`"
    end)

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate55.igniter()
    assert_unchanged(rerun, ["lib/lett/farms/farm.ex"])
    refute Enum.any?(rerun.notices, &(&1 =~ "set `persist_identifier false`"))
  end

  test "keeps the advice when it cannot read the router" do
    igniter = migrate(Map.delete(files(), @router_path))

    assert_unchanged(igniter, ["lib/lett/farms/farm.ex"])
    assert_has_warning(igniter, &(&1 =~ "could not read the router's admin routes"))
  end

  defp files do
    %{
      @router_path => @router,
      "lib/lett/farms/farm.ex" => @farm,
      "lib/lett/menu/category.ex" => blueprint("Menu", "Category", "category", ~s(,\n    router_scope: :menu)),
      "lib/lett/menu/menuitem.ex" => blueprint("Menu", "Menuitem", "menuitem"),
      "lib/lett/articles/category.ex" => blueprint("Articles", "Category", "category"),
      "lib/lett/prices/price.ex" => blueprint("Prices", "Price", "price", "", "data_layer :embedded"),
      "lib/lett/projects/inline_row.ex" => blueprint("Projects", "InlineRow", "inline_row", "", "identifier false"),
      "lib/lett/pages/landing.ex" => blueprint("Pages", "Landing", "landing", "", "persist_identifier true"),
      "lib/lett/stores/store.ex" =>
        blueprint("Stores", "Store", "store", "", ~s(absolute_url "{% route store_path show { entry.slug } %}")),
      "lib/lett_admin/live/menu/menuitem_list_live.ex" => """
      defmodule LettAdmin.Menu.MenuitemListLive do
        use BrandoAdmin.LiveView.Listing, schema: Lett.Menu.Menuitem
      end
      """
    }
  end

  defp blueprint(domain, schema, singular, options \\ "", body \\ ~s(identifier "{{ entry.name }}")) do
    """
    defmodule Lett.#{domain}.#{schema} do
      use Brando.Blueprint,
        application: "Lett",
        domain: "#{domain}",
        schema: "#{schema}",
        singular: "#{singular}",
        plural: "#{singular}s"#{options}

      #{body}
    end
    """
  end

  defp migrate(files) do
    [app_name: :lett, files: Map.put(files, ".formatter.exs", @formatter)]
    |> test_project()
    |> include_test_files()
    |> Migrate55.igniter()
  end

  defp source(igniter, path), do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  defp include_test_files(igniter) do
    Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, &Igniter.include_existing_file(&2, &1))
  end
end
