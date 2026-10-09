defmodule BrandoAdmin.Components.Form.MetaDrawerTest do
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import Ecto.Changeset, only: [change: 1]
  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias BrandoAdmin.Components.Form.MetaDrawer
  alias Phoenix.LiveView.JS

  defp put_ai do
    put_test_env(Brando.AI,
      default_model: "openai:gpt-4o-mini",
      providers: [openai: [api_key: "test-openai-key"]]
    )
  end

  # The actions the drawer offers on `field`, in order
  defp actions(html, field) do
    ~r/<button[^>]*phx-click="run_field_action"[^>]*>/
    |> Regex.scan(html)
    |> List.flatten()
    |> Enum.filter(&(&1 =~ ~s(phx-value-field="#{field}")))
    |> Enum.map(&(Regex.run(~r/phx-value-action="(\w+)"/, &1, capture: :all_but_first) |> hd()))
    |> Enum.uniq()
  end

  test "the site prompts give the meta fields a Generate action, not a button that writes the field" do
    put_ai()

    html =
      render_component(&MetaDrawer.render/1, %{
        id: "meta-drawer",
        form: %Brando.Pages.Page{} |> change() |> to_form(as: :page),
        blueprint: nil,
        form_cid: "form-target",
        form_id: "page_form",
        parent_uploads: %{},
        current_user: nil,
        close: %JS{}
      })

    assert actions(html, "meta_title") == ["generate"]
    assert actions(html, "meta_description") == ["generate"]
    assert html =~ ~s(id="page_meta_title-meta-ai-actions")
    refute html =~ "ai_generate_input"
  end

  test "a meta field's own actions come first, and the site prompt's Generate after them" do
    put_ai()

    html =
      render_component(&MetaDrawer.render/1, %{
        id: "meta-drawer",
        form: %Brando.MetaDrawerTest.ActionsArticle{} |> change() |> to_form(as: :actions_article),
        blueprint: Brando.MetaDrawerTest.ActionsArticle.__form__(),
        form_cid: "form-target",
        form_id: "actions_article_form",
        parent_uploads: %{},
        current_user: nil,
        close: %JS{}
      })

    assert actions(html, "meta_description") == ["shorten", "generate"]
    assert actions(html, "meta_title") == []
  end

  test "outside an entry form, or without AI, the meta fields have no actions" do
    put_ai()
    refute render_drawer(%Brando.Pages.Page{}, :page) =~ "run_field_action"

    put_test_env(Brando.AI, enabled: false)

    html =
      render_component(&MetaDrawer.render/1, %{
        id: "meta-drawer",
        form: %Brando.Pages.Page{} |> change() |> to_form(as: :page),
        blueprint: nil,
        form_cid: "form-target",
        form_id: "page_form",
        parent_uploads: %{},
        current_user: nil,
        close: %JS{}
      })

    refute html =~ "run_field_action"
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
