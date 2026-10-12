defmodule Mix.Tasks.Brando.Migrate54AdminFormViewsTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate54

  @router_path "lib/lett_web/router.ex"

  @router """
  defmodule LettWeb.Router do
    use BrandoWeb, :router

    import Brando.Router

    admin_routes do
      live "/", LettAdmin.DashboardLive

      scope "/banners", LettAdmin.Banners do
        live "/banners", BannerListLive
        live "/banners/create", BannerCreateLive
        live "/banners/update/:entry_id", BannerUpdateLive
      end

      scope "/menu", LettAdmin.Menu do
        live "/categories", CategoryListLive
        live "/categories/create", CategoryCreateLive
        live "/categories/update/:entry_id", CategoryUpdateLive

        live "/menuitems", MenuitemListLive
        live "/menuitems/create", MenuitemCreateLive
        live "/menuitems/update/:entry_id", MenuitemUpdateLive
      end

      live "/articles/categories", LettAdmin.Articles.CategoryListLive
      live "/articles/categories/create", LettAdmin.Articles.CategoryCreateLive
      live "/articles/categories/update/:entry_id", LettAdmin.Articles.CategoryUpdateLive
    end
  end
  """

  # Phoenix's `import_deps` formatting, without the dependency.
  @formatter """
  [
    inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
    locals_without_parens: [live: 2, live: 3, live: 4, get: 3, get: 4]
  ]
  """

  @views [
    {"banners/banner", "Banners", "Banner"},
    {"menu/category", "Menu", "Category"},
    {"menu/menuitem", "Menu", "Menuitem"},
    {"articles/category", "Articles", "Category"}
  ]

  test "writes each FormLive in the directory of the UpdateLive it replaces" do
    igniter = migrate(views())

    for {path, _domain, _schema} <- @views do
      assert "lib/lett_admin/live/#{path}_create_live.ex" in igniter.rms
      assert "lib/lett_admin/live/#{path}_update_live.ex" in igniter.rms
    end

    assert_has_notice(igniter, fn notice ->
      notice =~ "LettAdmin.Banners.BannerFormLive (lib/lett_admin/live/banners/banner_form_live.ex)" and
        notice =~ "LettAdmin.Menu.MenuitemFormLive (lib/lett_admin/live/menu/menuitem_form_live.ex)"
    end)

    written = igniter |> apply_igniter!() |> Map.fetch!(:assigns) |> Map.fetch!(:test_files)

    for {path, domain, schema} <- @views do
      assert written["lib/lett_admin/live/#{path}_form_live.ex"] =~ "defmodule LettAdmin.#{domain}.#{schema}FormLive do"
      refute Map.has_key?(written, "lib/lett_admin/#{path}_form_live.ex")
      refute Map.has_key?(written, "lib/lett_admin/live/#{path}_update_live.ex")
    end
  end

  test "scopes a domain's admin routes `as:` when its FormLive shares a route helper" do
    igniter = migrate(Map.merge(views(), blueprints()))

    router = source(igniter, @router_path)
    assert router =~ ~s(scope "/menu", LettAdmin.Menu, as: :menu do\n      live "/categories", CategoryListLive\n)
    assert router =~ ~s(scope "/banners", LettAdmin.Banners do)
    assert router =~ ~s|live "/articles/categories/update/:entry_id", LettAdmin.Articles.CategoryFormLive, :update|

    for {schema, plural} <- [{"Category", "categories"}, {"Menuitem", "menuitems"}] do
      assert source(igniter, "lib/lett/menu/#{Macro.underscore(schema)}.ex") =~ """
               use Brando.Blueprint,
                 application: "Lett",
                 domain: "Menu",
                 schema: "#{schema}",
                 singular: "#{Macro.underscore(schema)}",
                 plural: "#{plural}",
                 router_scope: :menu

             """
    end

    refute source(igniter, "lib/lett/articles/category.ex") =~ "router_scope"
    refute Enum.any?(igniter.warnings, &(&1 =~ "share a route helper"))

    assert_has_notice(igniter, fn notice ->
      notice =~ "admin_category_form_path" and notice =~ ~s(#{@router_path}:15: scope "/menu", LettAdmin.Menu, as: :menu) and
        notice =~ "router_scope: :menu" and notice =~ "Lett.Menu.Category, Lett.Menu.Menuitem"
    end)

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate54.igniter()
    assert_unchanged(rerun, [@router_path, "lib/lett/menu/category.ex", "lib/lett/menu/menuitem.ex"])
  end

  test "keeps the shared route helper warning when the scope holds another domain's routes" do
    router =
      String.replace(
        @router,
        ~s(live "/menuitems", MenuitemListLive),
        ~s(live "/menuitems", MenuitemListLive\n      get "/export", MenuExportController, :export)
      )

    igniter = migrate(views() |> Map.merge(blueprints()) |> Map.put(@router_path, router))

    assert source(igniter, @router_path) =~ ~s(scope "/menu", LettAdmin.Menu do)
    refute source(igniter, "lib/lett/menu/category.ex") =~ "router_scope"

    assert_has_warning(igniter, fn warning ->
      warning =~ "share a route helper" and
        warning =~ "Lett.Articles.Category, Lett.Menu.Category: admin_category_form_path" and
        warning =~ "#{@router_path}:18" and warning =~ "#{@router_path}:28" and
        warning =~ "router_scope: :menu"
    end)
  end

  test "keeps the shared route helper warning when other code names the scope's route helpers" do
    helper_call = """
    defmodule LettAdmin.ShortcutsTest do
      test "menu" do
        LettWeb.Router.Helpers.admin_live_path(
          socket,
          LettAdmin.Menu.MenuitemListLive
        )
      end
    end
    """

    template = """
    <.link navigate={Routes.admin_menuitem_form_path(@socket, :update, 1)}>Edit</.link>
    """

    files =
      views()
      |> Map.merge(blueprints())
      |> Map.put("test/lett_admin/shortcuts_test.exs", helper_call)
      |> Map.put("lib/lett_web/components/edit.html.heex", template)

    igniter = migrate(files)

    assert source(igniter, @router_path) =~ ~s(scope "/menu", LettAdmin.Menu do)

    assert_has_warning(igniter, fn warning ->
      warning =~ "share a route helper" and warning =~ "test/lett_admin/shortcuts_test.exs:3" and
        warning =~ "lib/lett_web/components/edit.html.heex:1"
    end)
  end

  defp blueprints do
    for {domain, schema, plural} <- [
          {"Menu", "Category", "categories"},
          {"Menu", "Menuitem", "menuitems"},
          {"Articles", "Category", "categories"}
        ],
        into: %{} do
      singular = Macro.underscore(schema)

      {"lib/lett/#{Macro.underscore(domain)}/#{singular}.ex",
       """
       defmodule Lett.#{domain}.#{schema} do
         @moduledoc \"\"\"
         Blueprint for #{schema}
         \"\"\"

         use Brando.Blueprint,
           application: "Lett",
           domain: "#{domain}",
           schema: "#{schema}",
           singular: "#{singular}",
           plural: "#{plural}"

         identifier "{{ entry.name }}"
       end
       """}
    end
  end

  defp list_views do
    for {path, domain, schema} <- @views, into: %{} do
      {"lib/lett_admin/live/#{path}_list_live.ex",
       """
       defmodule LettAdmin.#{domain}.#{schema}ListLive do
         use BrandoAdmin.LiveView.Listing, schema: Lett.#{domain}.#{schema}
       end
       """}
    end
  end

  defp views do
    for {path, domain, schema} <- @views,
        action <- [:create, :update],
        into: Map.put(list_views(), @router_path, @router) do
      module = "LettAdmin.#{domain}.#{schema}#{action |> to_string() |> Macro.camelize()}Live"
      {"lib/lett_admin/live/#{path}_#{action}_live.ex", admin_view(module, "Lett.#{domain}.#{schema}", action)}
    end
  end

  defp admin_view(module, schema, action) do
    singular = schema |> String.split(".") |> List.last() |> Macro.underscore()
    entry_id = if action == :update, do: "\n      entry_id={@entry_id}", else: ""
    presences = if action == :update, do: "\n      presences={@presences}", else: ""

    """
    defmodule #{module} do
      use BrandoAdmin.LiveView.Form, schema: #{schema}
      alias BrandoAdmin.Components.Form
      import LettAdmin.Gettext

      def render(assigns) do
        ~H\"\"\"
        <.live_component module={Form}
          id="#{singular}_form"#{entry_id}
          current_user={@current_user}#{presences}
          schema={@schema}>
          <:header>
            <%= gettext("#{action} #{singular}") %>
          </:header>
        </.live_component>
        \"\"\"
      end
    end
    """
  end

  defp migrate(files) do
    [app_name: :lett, files: Map.put_new(files, ".formatter.exs", @formatter)]
    |> test_project()
    |> include_test_files()
    |> Migrate54.igniter()
  end

  defp source(igniter, path), do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  defp include_test_files(igniter) do
    Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, &Igniter.include_existing_file(&2, &1))
  end
end
