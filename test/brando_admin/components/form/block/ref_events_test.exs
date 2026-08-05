defmodule BrandoAdmin.Components.Form.Block.RefEventsTest do
  # Regression coverage for the ref-management block events.
  #
  # `refs` is `relation :refs, :has_many` (Brando.Content.Block), but these three
  # handlers drove it with `Changeset.get_embed/put_embed`, which raises
  # "expected refs to be an embed, got: assoc" and takes the editor LiveView
  # down — discarding every unsaved change in that process. All three are
  # reachable from live buttons in `block/render.ex`.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Blocks, as: ContentBlocks
  alias Brando.Factory
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Block.Events
  alias BrandoAdmin.Components.Form.BlockField
  alias Ecto.Changeset

  defp create_module(user) do
    {:ok, module} =
      Brando.Content.create_module(
        %{
          name: %{"en" => "Two refs"},
          namespace: %{"en" => "test"},
          help_text: %{"en" => "help"},
          class: "tworefs",
          code: "<div>{% ref refs.header %}{% ref refs.body %}</div>",
          refs: [
            %{
              name: "header",
              uid: "refheader1",
              description: "header ref",
              data: %{type: "text", data: %{text: "Default header", type: "paragraph"}}
            },
            %{
              name: "body",
              uid: "refbody001",
              description: "body ref",
              data: %{type: "text", data: %{text: "Default body", type: "paragraph"}}
            }
          ],
          vars: []
        },
        user
      )

    module
  end

  # A child block changeset — refs live directly on it.
  defp child_changeset(module, user) do
    BlockField.build_block(module.id, user.id, nil, "Elixir.Brando.Pages.Page.Blocks", :module)
  end

  # A root (entry_block) changeset — refs live on the nested `:block` assoc.
  defp root_changeset(module, user) do
    %Brando.Pages.Page.Blocks{}
    |> Changeset.change()
    |> Changeset.put_assoc(:block, child_changeset(module, user))
  end

  defp base_changeset(:root, module, user), do: root_changeset(module, user)
  defp base_changeset(_child, module, user), do: child_changeset(module, user)

  defp socket_for(changeset, belongs_to, module) do
    uid =
      case belongs_to do
        :root -> changeset |> Changeset.get_assoc(:block) |> Changeset.get_field(:uid)
        _ -> Changeset.get_field(changeset, :uid)
      end

    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(:form, Block.build_form_from_changeset(changeset, uid, belongs_to))
    |> Phoenix.Component.assign(:belongs_to, belongs_to)
    |> Phoenix.Component.assign(:module_id, module.id)
    |> Phoenix.Component.assign(:uid, uid)
    |> Phoenix.Component.assign(:form_id, "page_form")
    |> Phoenix.Component.assign(:block_field, "blocks")
  end

  # Read the resulting refs back out of whichever level they live on.
  defp refs_of(socket, :root) do
    socket.assigns.form.source
    |> Changeset.get_assoc(:block)
    |> Changeset.get_assoc(:refs)
  end

  defp refs_of(socket, _child) do
    Changeset.get_assoc(socket.assigns.form.source, :refs)
  end

  defp ref_names(socket, belongs_to) do
    socket
    |> refs_of(belongs_to)
    |> Enum.reject(&(&1.action == :replace))
    |> Enum.map(&Changeset.get_field(&1, :name))
    |> Enum.sort()
  end

  # Drop every ref but "header", so "body" is missing and must be re-fetched.
  defp drop_body_ref(changeset, :root) do
    block_cs = Changeset.get_assoc(changeset, :block)
    Changeset.put_assoc(changeset, :block, drop_body_ref(block_cs, :child))
  end

  defp drop_body_ref(changeset, _child) do
    kept =
      changeset
      |> Changeset.get_assoc(:refs)
      |> Enum.filter(&(Changeset.get_field(&1, :name) == "header"))

    Changeset.put_assoc(changeset, :refs, kept)
  end

  for belongs_to <- [:root, :child] do
    describe "ref events (#{belongs_to} block)" do
      setup do
        user = Factory.insert(:random_user)
        module = create_module(user)
        {:ok, user: user, module: module}
      end

      test "fetch_missing_refs re-adds a missing ref", %{user: user, module: module} do
        belongs_to = unquote(belongs_to)

        changeset = belongs_to |> base_changeset(module, user) |> drop_body_ref(belongs_to)

        socket = socket_for(changeset, belongs_to, module)
        assert ref_names(socket, belongs_to) == ["header"]

        assert {:halt, socket} = Events.handle_block_event("fetch_missing_refs", %{}, socket)
        assert ref_names(socket, belongs_to) == ["body", "header"]
      end

      test "fetch_missing_refs is a no-op when nothing is missing", %{user: user, module: module} do
        belongs_to = unquote(belongs_to)

        changeset = base_changeset(belongs_to, module, user)

        socket = socket_for(changeset, belongs_to, module)

        assert {:halt, socket} = Events.handle_block_event("fetch_missing_refs", %{}, socket)
        assert ref_names(socket, belongs_to) == ["body", "header"]
      end

      test "reset_ref restores a single ref from the module", %{user: user, module: module} do
        belongs_to = unquote(belongs_to)

        changeset = base_changeset(belongs_to, module, user)

        socket = socket_for(changeset, belongs_to, module)

        assert {:halt, socket} =
                 Events.handle_block_event("reset_ref", %{"id" => "header"}, socket)

        assert ref_names(socket, belongs_to) == ["body", "header"]
      end

      test "reset_refs restores every ref from the module", %{user: user, module: module} do
        belongs_to = unquote(belongs_to)

        changeset = belongs_to |> base_changeset(module, user) |> drop_body_ref(belongs_to)

        socket = socket_for(changeset, belongs_to, module)

        assert {:halt, socket} = Events.handle_block_event("reset_refs", %{}, socket)
        assert ref_names(socket, belongs_to) == ["body", "header"]
      end
    end
  end

  test "refs survive a save after fetch_missing_refs" do
    user = Factory.insert(:random_user)
    module = create_module(user)
    page = Factory.insert(:page, creator: user)

    changeset = drop_body_ref(root_changeset(module, user), :root)
    socket = socket_for(changeset, :root, module)

    assert {:halt, socket} = Events.handle_block_event("fetch_missing_refs", %{}, socket)

    entry_block_cs =
      socket.assigns.form.source
      |> Changeset.put_change(:entry_id, page.id)
      |> Changeset.put_change(:sequence, 0)

    updated =
      [entry_block_cs]
      |> ContentBlocks.reject_deleted(true)
      |> ContentBlocks.strip_render_artifacts()
      |> Enum.map(&Brando.Utils.set_action/1)

    assert {:ok, _} =
             page
             |> Brando.Repo.preload(:entry_blocks)
             |> Changeset.change()
             |> Changeset.put_assoc(:entry_blocks, updated)
             |> Brando.Repo.update()

    [entry_block] =
      Brando.Pages.Page.Blocks
      |> Brando.Repo.all()
      |> Brando.Repo.preload(block: :refs)

    assert entry_block.block.refs |> Enum.map(& &1.name) |> Enum.sort() == ["body", "header"]
  end
end
