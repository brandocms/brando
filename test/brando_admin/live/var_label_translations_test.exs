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

  test "validation then a reverted edit saves complete translations without unused metadata",
       %{conn: conn, module: module} do
    put_test_env(:admin_languages, [[value: "en", text: "English"], [value: "no", text: "Norsk"]])

    module =
      module
      |> Ecto.Changeset.change(
        name: %{"en" => "Hero", "no" => "Hovedfelt", "de" => "Titel"},
        namespace: %{"en" => "Content", "no" => "Innhold"},
        help_text: %{"en" => "Help", "no" => "Hjelp", "de" => "Hilfe"}
      )
      |> Repo.update!()

    {:ok, view, _html} = live(conn, "/admin/config/content/modules/update/#{module.id}")

    # LiveViewTest does not add the browser's unused-field markers. Add
    # them to validation, then save only the controls the view renders.
    unused = %{"_unused_en" => "", "_unused_no" => ""}

    metadata = %{
      "module" => %{
        "name" => unused,
        "namespace" => unused,
        "help_text" => unused,
        "vars" => %{"0" => %{"label" => unused}}
      }
    }

    for class <- ["temporarily-edited", module.class || ""] do
      view
      |> form("#module_form", %{"module" => %{"class" => class}})
      |> render_change(metadata)
    end

    view |> form("#module_form") |> render_submit()

    saved = Repo.preload(Repo.get!(Module, module.id), :vars)
    assert saved.name == module.name
    assert saved.namespace == module.namespace
    assert saved.help_text == module.help_text
    assert Enum.map(saved.vars, & &1.label) == Enum.map(module.vars, & &1.label)
    assert saved.version == module.version
  end

  # The lint was a browser test in configuration/modules.spec.js; typing
  # into CodeMirror only writes the code textarea this changes.
  test "the editor warns when a ref sits inside a conditional, until it is declared at the top level",
       %{conn: conn, module: module} do
    {:ok, view, _html} = live(conn, "/admin/config/content/modules/update/#{module.id}")
    refute has_element?(view, ".module-code-lint")

    change_code(view, "{% if show %}{% ref refs.text %}{% endif %}")
    assert has_element?(view, ".module-code-lint", "Reference text sits inside a conditional")
    assert has_element?(view, ".module-code-lint", "headless_ref refs.text")

    change_code(view, "{% headless_ref refs.text %}{% if refs.text.active %}shown{% endif %}")
    refute has_element?(view, ".module-code-lint")
  end

  defp change_code(view, code) do
    view |> form("#module_form-el form.main-form", %{"module" => %{"code" => code}}) |> render_change()
  end
end
