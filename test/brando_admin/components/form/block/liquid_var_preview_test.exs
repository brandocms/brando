defmodule BrandoAdmin.Components.Form.Block.LiquidVarPreviewTest do
  # Editing a string var must update the inline Liquid preview (`liquid_splits`)
  # for both block shapes. A child block's inputs are named
  # `child_block[vars][i][value]`; a root block wraps its block in an
  # entry_block, so its inputs are `entry_block[block][vars][i][value]`. The
  # root shape used to fall through to the no-op clause, leaving `{{ caption }}`
  # stale until save and reopen — issue #2797.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.BlockField
  alias Ecto.Changeset
  alias Phoenix.Component

  defp create_module(user) do
    {:ok, module} =
      Brando.Content.create_module(
        %{
          name: %{"en" => "Caption var"},
          namespace: %{"en" => "test"},
          help_text: %{"en" => "help"},
          class: "captionvar",
          code: "<figure>{% ref refs.heading %}<figcaption>{{ caption }}</figcaption></figure>",
          refs: [
            %{
              name: "heading",
              uid: "refheading",
              description: "heading ref",
              data: %{type: "header", data: %{text: "Heading", level: 2}}
            }
          ],
          vars: [
            %{type: :string, key: "caption", label: "Caption", value: "Original caption"}
          ]
        },
        user
      )

    module
  end

  defp child_changeset(module, user) do
    BlockField.build_block(module.id, user.id, nil, "Elixir.Brando.Pages.Page.Blocks", :module)
  end

  defp root_changeset(module, user) do
    %Brando.Pages.Page.Blocks{}
    |> Changeset.change()
    |> Changeset.put_assoc(:block, child_changeset(module, user))
  end

  defp socket_for(:root, module, user) do
    changeset = root_changeset(module, user)
    uid = changeset |> Changeset.get_assoc(:block) |> Changeset.get_field(:uid)
    build_socket(changeset, uid, :root, module)
  end

  defp socket_for(:child, module, user) do
    changeset = child_changeset(module, user)
    build_socket(changeset, Changeset.get_field(changeset, :uid), :child, module)
  end

  defp build_socket(changeset, uid, belongs_to, module) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:form, Block.build_form_from_changeset(changeset, uid, belongs_to))
    |> Component.assign(:belongs_to, belongs_to)
    |> Component.assign(:module_id, module.id)
    |> Component.assign(:uid, uid)
    |> Component.assign(:liquid_splits, [
      "<figure>",
      {:ref, "heading"},
      "<figcaption>",
      {:module_variable, "caption", "Original caption"},
      "</figcaption></figure>"
    ])
  end

  defp rendered_caption(socket) do
    Enum.find_value(socket.assigns.liquid_splits, fn
      {:module_variable, "caption", value} -> value
      _ -> nil
    end)
  end

  setup do
    user = Factory.insert(:random_user)
    {:ok, user: user, module: create_module(user)}
  end

  test "a root block's var edit updates the rendered variable", %{user: user, module: module} do
    socket = socket_for(:root, module, user)

    # What the browser submits for a root block: the form name, then the
    # entry_block's `block` assoc, then the var.
    target = ["entry_block", "block", "vars", "0", "value"]
    params = %{"block" => %{"vars" => %{"0" => %{"value" => "Edited caption"}}}}

    socket = Block.maybe_update_liquex_block_var(socket, target, params)

    assert rendered_caption(socket) == "Edited caption"
  end

  test "a child block's var edit updates the rendered variable", %{user: user, module: module} do
    socket = socket_for(:child, module, user)

    target = ["child_block", "vars", "0", "value"]
    params = %{"vars" => %{"0" => %{"value" => "Edited caption"}}}

    socket = Block.maybe_update_liquex_block_var(socket, target, params)

    assert rendered_caption(socket) == "Edited caption"
  end

  test "an unrelated target leaves the rendered variable alone", %{user: user, module: module} do
    socket = socket_for(:root, module, user)

    target = ["entry_block", "block", "description"]
    params = %{"block" => %{"description" => "typing"}}

    socket = Block.maybe_update_liquex_block_var(socket, target, params)

    assert rendered_caption(socket) == "Original caption"
  end

  test "a var index the changeset does not have is skipped, not crashed", %{user: user, module: module} do
    socket = socket_for(:root, module, user)

    target = ["entry_block", "block", "vars", "7", "value"]
    params = %{"block" => %{"vars" => %{"7" => %{"value" => "Nope"}}}}

    socket = Block.maybe_update_liquex_block_var(socket, target, params)

    assert rendered_caption(socket) == "Original caption"
  end
end
