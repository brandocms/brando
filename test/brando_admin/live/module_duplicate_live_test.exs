defmodule BrandoAdmin.ModuleDuplicateLiveTest do
  # The module listing's Duplicate action (`duplicate_entry`) calls
  # `Brando.Content.duplicate_module/2`: it used to fail on the module's
  # unique uid, and lost a multi module's children and module sets.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Content
  alias Brando.Content.Module

  setup %{current_user: user} do
    {:ok, parent} =
      Content.create_module(
        %{
          name: %{"en" => "Cards"},
          namespace: %{"en" => "general"},
          help_text: %{"en" => "Cards"},
          class: "cards",
          code: "{{ content }}",
          multi: true,
          write_with_ai: true,
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Text"}}}]
        },
        user
      )

    {:ok, _child} =
      Content.create_module(
        %{
          name: %{"en" => "Card"},
          namespace: %{"en" => "general"},
          help_text: %{"en" => "Card"},
          class: "card",
          code: "{% ref refs.body %}",
          parent_id: parent.id,
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Card"}}}]
        },
        user
      )

    %{parent: parent}
  end

  test "Duplicate in the module listing copies the module with its children", %{conn: conn, parent: parent} do
    {:ok, view, _html} = live(conn, "/admin/config/content/modules")
    await_selector(view, ".list-row")

    view |> element("#action_default_duplicate_entry_#{parent.id}") |> render_click()

    copy =
      Repo.one!(
        from m in Module, where: m.class == "cards-copy" and is_nil(m.parent_id), preload: [:refs, children: :refs]
      )

    assert copy.id != parent.id
    assert copy.uid != parent.uid
    assert copy.write_with_ai
    assert [%{name: "body"}] = copy.refs
    assert [%{class: "card", refs: [%{name: "body"}]}] = copy.children
    assert Process.alive?(view.pid)
  end
end
