defmodule BrandoAdmin.Components.Form.MetaDrawerTest do
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import Ecto.Changeset, only: [change: 1]
  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias BrandoAdmin.Components.Form.MetaDrawer
  alias Phoenix.LiveView.JS

  test "renders AI action for meta fields from trait defaults" do
    put_test_env(Brando.AI,
      default_model: "openai:gpt-4o-mini",
      providers: [openai: [api_key: "test-openai-key"]]
    )

    form =
      %Brando.Pages.Page{}
      |> change()
      |> to_form(as: :page)

    html =
      render_component(&MetaDrawer.render/1, %{
        id: "meta-drawer",
        form: form,
        blueprint: nil,
        form_cid: "form-target",
        parent_uploads: %{},
        current_user: nil,
        close: %JS{}
      })

    assert html =~ ~s(phx-value-field_key="meta_title")
    assert html =~ ~s(phx-value-field_key="meta_description")
    assert html =~ ~s(phx-click="ai_generate_input")
  end

  defp render_drawer(data, as) do
    render_component(&MetaDrawer.render/1, %{
      id: "meta-drawer",
      form: data |> change() |> to_form(as: as),
      blueprint: nil,
      form_cid: "form-target",
      parent_uploads: %{},
      current_user: nil,
      close: %JS{}
    })
  end

  test "a blueprint with a json_ld_schema gets the structured data tab, closed until opened" do
    html = render_drawer(%Brando.Pages.Page{id: 4}, :page)

    assert html =~ ~s(data-testid="meta-tab-structured-data")
    assert html =~ ~s(id="meta-drawer-structured-data-pane")
    assert html =~ ~s(phx-hook="Brando.StructuredData")
    # Nothing is read until the tab opens.
    refute html =~ "structured-data-node"
    # The meta fields stay the first tab.
    assert html =~ ~s(id="meta-drawer-tab-meta" type="button" aria-pressed="true")
  end

  test "a blueprint without one has the meta fields alone" do
    html = render_drawer(%Brando.Sites.SEO{}, :seo)

    refute html =~ "meta-tab-structured-data"
    refute html =~ "Brando.StructuredData"
    assert html =~ "meta_title"
  end
end
