defmodule BrandoAdmin.Components.Form.MetaDrawerTest do
  use ExUnit.Case, async: false

  import Ecto.Changeset, only: [change: 1]
  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias BrandoAdmin.Components.Form.MetaDrawer
  alias Phoenix.LiveView.JS

  setup do
    original_brando_ai_cfg = Application.get_env(:brando, Brando.AI)

    on_exit(fn ->
      restore_env(:brando, Brando.AI, original_brando_ai_cfg)
    end)

    :ok
  end

  test "renders AI action for meta fields from trait defaults" do
    Application.put_env(:brando, Brando.AI,
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

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
