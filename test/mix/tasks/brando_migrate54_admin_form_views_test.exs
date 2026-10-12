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

  defp views do
    for {path, domain, schema} <- @views, action <- [:create, :update], into: %{@router_path => @router} do
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
    [app_name: :lett, files: files]
    |> test_project()
    |> include_test_files()
    |> Migrate54.igniter()
  end

  defp include_test_files(igniter) do
    Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, &Igniter.include_existing_file(&2, &1))
  end
end
