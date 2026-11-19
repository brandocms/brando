defmodule BrandoAdmin.Live.Content.ModuleDeleteConfirmTest do
  # Deleting a reference or a variable in the module editor asks first, in the
  # admin's dialog (assets/src/confirm.js), and the dialog names what goes.
  use Brando.LiveCase

  alias Brando.Content.Ref
  alias Brando.Content.Var
  alias Brando.Villain.Blocks.TextBlock
  alias Ecto.Changeset

  setup do
    module =
      :module
      |> Factory.build(%{code: "<div>{% ref refs.intro %}{{ size }}</div>"})
      |> Changeset.change()
      |> Changeset.put_assoc(:refs, [
        %Ref{
          name: "intro",
          uid: "uid-intro",
          data: %TextBlock{type: "text", data: %TextBlock.Data{text: "Hello"}},
          sequence: 0
        }
      ])
      |> Changeset.put_assoc(:vars, [%Var{key: "size", type: "string", label: %{"en" => "Size"}}])
      |> Brando.Repo.insert!()

    %{module: module}
  end

  test "deleting a reference or a variable asks first", %{conn: conn, module: module} do
    {:ok, view, _html} = live(conn, "/admin/config/content/modules/update/#{module.id}")

    assert has_element?(
             view,
             ~s(button.module-danger[name="module[drop_ref_ids][]"][value="0"]) <>
               ~s([data-confirm="Delete reference intro?"][data-confirm-ok="Delete reference"][data-confirm-destructive])
           )

    assert has_element?(
             view,
             ~s(button.var-chip-danger[name="module[drop_var_ids][]"][value="0"]) <>
               ~s([data-confirm="Delete variable size?"][data-confirm-ok="Delete variable"][data-confirm-destructive])
           )
  end
end
