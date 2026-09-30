defmodule BrandoAdmin.VarLabelTranslationsTest do
  # A var's label is a language map. The module editor edits one label per
  # admin language, and saving keeps both.
  use Brando.LiveCase

  alias Brando.Content.Module
  alias Brando.Repo

  setup %{current_user: user} do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Hero"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{{ size }}",
          refs: [],
          vars: [%{key: "size", type: "string", label: %{"en" => "Size", "no" => "Størrelse"}}]
        ),
        user
      )

    %{module: module}
  end

  test "the module editor shows a label input per admin language", %{conn: conn, module: module} do
    {:ok, _view, html} = live(conn, "/admin/config/content/modules/update/#{module.id}")

    assert html =~
             ~r/name="module\[vars\]\[0\]\[label\]\[en\]"[^>]*value="Size"|value="Size"[^>]*name="module\[vars\]\[0\]\[label\]\[en\]"/

    assert html =~ "Størrelse"
  end

  test "saving keeps both languages", %{conn: conn, module: module} do
    {:ok, view, _html} = live(conn, "/admin/config/content/modules/update/#{module.id}")

    view
    |> form("#module_form-el form.main-form", %{
      "module" => %{"vars" => %{"0" => %{"label" => %{"en" => "Width", "no" => "Bredde"}}}}
    })
    |> render_submit()

    assert [%{label: %{"en" => "Width", "no" => "Bredde"}}] =
             Repo.preload(Repo.get!(Module, module.id), :vars, force: true).vars
  end
end
