defmodule Brando.Doctor.AdminRoutesTest.Articles.Category do
  @moduledoc false
  use Brando.Blueprint,
    application: "DoctorRoutes",
    domain: "Articles",
    schema: "Category",
    singular: "category",
    plural: "categories",
    gettext_module: Brando.Gettext
end

defmodule Brando.Doctor.AdminRoutesTest.Menu.Category do
  @moduledoc false
  use Brando.Blueprint,
    application: "DoctorRoutes",
    domain: "Menu",
    schema: "Category",
    singular: "category",
    plural: "categories",
    gettext_module: Brando.Gettext,
    router_scope: :menu
end

defmodule Brando.Doctor.AdminRoutesTest do
  use ExUnit.Case, async: true

  alias __MODULE__.Articles.Category, as: ArticleCategory
  alias __MODULE__.Menu.Category, as: MenuCategory
  alias Brando.Doctor.Checks.AdminRoutes
  alias Brando.Doctor.Result

  defmodule ArticleCategoryListLive do
    def __authorization_resource__, do: {:listing, ArticleCategory}
  end

  defmodule ArticleCategoryUpdateLive do
    def __authorization_resource__, do: {:form, ArticleCategory}
  end

  defmodule MenuCategoryFormLive do
    def __authorization_resource__, do: {:form, MenuCategory}
  end

  defmodule PageListLive do
    def __authorization_resource__, do: {:listing, Brando.Pages.Page}
  end

  defp live(helper, action, view),
    do: %{helper: helper, plug_opts: action, metadata: %{phoenix_live_view: {view, action, [], %{}}}}

  test "names a Blueprint whose listing links to a form route the router does not define" do
    routes = [
      live("admin_live", ArticleCategoryListLive, ArticleCategoryListLive),
      live("admin_category_update", nil, ArticleCategoryUpdateLive),
      %{helper: "page", plug_opts: :show, metadata: %{}},
      live("admin_live", PageListLive, PageListLive)
    ]

    assert AdminRoutes.missing_routes(routes) == [{ArticleCategory, [admin_category_form_path: :update]}]

    assert %Result{status: :error, summary: "1 Blueprint links to admin routes the router does not define"} =
             result = AdminRoutes.evaluate(AdminRoutes.missing_routes(routes))

    assert result.items == ["Brando.Doctor.AdminRoutesTest.Articles.Category: admin_category_form_path (:update)"]
    assert result.fix =~ "<Name>FormLive, :update"
    assert result.fix =~ "router_scope"
  end

  test "follows a Blueprint's router_scope" do
    unscoped = [live("admin_category_form", :update, MenuCategoryFormLive)]
    assert AdminRoutes.missing_routes(unscoped) == [{MenuCategory, [admin_menu_category_form_path: :update]}]

    scoped = [live("admin_menu_category_form", :update, MenuCategoryFormLive)]
    assert AdminRoutes.missing_routes(scoped) == []
    assert %Result{status: :ok} = AdminRoutes.evaluate([])
  end

  test "Brando.Blueprint.admin_editor?/2 agrees: an editor is an :update form route" do
    update = [live("admin_category_form", :update, ArticleCategoryUpdateLive)]
    # A create-only route still exports the helper at arity 3 (with params).
    create_only = [live("admin_category_form", :create, ArticleCategoryUpdateLive)]

    assert Brando.Blueprint.admin_editor?(ArticleCategory, update)
    refute Brando.Blueprint.admin_editor?(ArticleCategory, create_only)
    refute Brando.Blueprint.admin_editor?(ArticleCategory, [])
    refute Brando.Blueprint.admin_editor?(MenuCategory, update)

    assert AdminRoutes.missing_routes(update) == []
    assert AdminRoutes.missing_routes(create_only) == [{ArticleCategory, [admin_category_form_path: :update]}]
  end

  test "the Blueprint resolves its helpers by router_scope" do
    assert ArticleCategory.__admin_route_helper__(:update) == :admin_category_form_path
    assert ArticleCategory.__admin_route_helper__(:list) == :admin_live_path
    assert MenuCategory.__admin_route_helper__(:create) == :admin_menu_category_form_path
    assert MenuCategory.__admin_route_helper__(:list) == :admin_menu_live_path
  end

  test "is one of the default checks and passes on the test router" do
    assert AdminRoutes in Brando.Doctor.default_checks()
    assert %Result{status: :ok} = AdminRoutes.run(Brando.Doctor.Context.new(locale: "en"))
  end
end
