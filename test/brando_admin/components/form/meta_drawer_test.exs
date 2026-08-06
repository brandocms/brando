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
end
