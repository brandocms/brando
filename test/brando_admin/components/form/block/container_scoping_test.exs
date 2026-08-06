defmodule BrandoAdmin.Components.Form.Block.ContainerScopingTest do
  # Phase 3 / E2 in the form audit, plus two latent defects the review found
  # alongside it.
  #
  # `:containers` and `:palette_options` are ETS-backed lists, and an ETS read
  # copies the whole term onto the reading process's heap — once per block
  # component, all inside the single LiveView process. They are scoped to the
  # blocks that actually render them.
  #
  # The scoping was originally `type == :container or belongs_to == :root`, on
  # the premise that `container_config` is rendered by every root block. It is
  # not: `container_config` (`block/render.ex:526`) sits inside `container/1`,
  # whose only caller is `render(%{type: :container})`. Root module blocks were
  # still paying for both lists. These tests pin the corrected boundary, since
  # nothing else would notice it drifting back.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias BrandoAdmin.Components.Form.Block

  setup do
    {:ok, user: Factory.insert(:random_user)}
  end

  defp socket_with(assigns) do
    defaults = %{
      container_id: nil,
      type: :module,
      belongs_to: :root,
      container_not_found: false,
      fragment_not_found: false
    }

    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(Map.merge(defaults, assigns))
  end

  describe "palette_options scoping" do
    test "a container block loads the palette list" do
      socket = Block.maybe_assign_container(socket_with(%{type: :container}))

      assert is_list(socket.assigns.palette_options)
    end

    test "a ROOT module block does not — `belongs_to` is not a reader" do
      socket = Block.maybe_assign_container(socket_with(%{type: :module, belongs_to: :root}))

      assert socket.assigns.palette_options == nil
    end

    test "nor does a child module block" do
      socket = Block.maybe_assign_container(socket_with(%{type: :module, belongs_to: :child}))

      assert socket.assigns.palette_options == nil
    end
  end

  describe "palette_options is nil, never []" do
    # `container_config` branches on `if @palette_options` to choose between the
    # palette <select> and a hidden carrier input. `[]` is truthy in Elixir, so
    # returning it renders a <select> with no options — which submits nothing for
    # `block[palette_id]`, dropping an already-set palette on the next validate.
    test "a container that disallows a custom palette gets nil, not an empty list", ctx do
      {:ok, container} =
        Brando.Content.create_container(
          %{
            name: "Scoping test container",
            namespace: "general",
            code: "<section>{{ content }}</section>",
            allow_custom_palette: false
          },
          ctx.user
        )

      socket =
        Block.maybe_assign_container(socket_with(%{type: :container, container_id: container.id}))

      refute socket.assigns.palette_options == []
      assert socket.assigns.palette_options == nil
    end
  end

  describe "a missing container or fragment does not crash the editor" do
    # `render(%{type: :container})` reads @container and @palette_options;
    # `render(%{type: :fragment})` reads @fragment. Setting only the not-found
    # flag left those unassigned, and there was no render clause matching the
    # flag — so a block referencing a deleted container raised KeyError mid-render
    # and took the editor LiveView down, unsaved block edits included.
    test "a deleted container still leaves :container and :palette_options assigned" do
      socket =
        Block.maybe_assign_container(socket_with(%{type: :container, container_id: 999_999_999}))

      assert socket.assigns.container_not_found
      assert Map.has_key?(socket.assigns, :container)
      assert Map.has_key?(socket.assigns, :palette_options)
    end

    test "a deleted fragment still leaves :fragment assigned" do
      socket =
        Block.maybe_assign_fragment(socket_with(%{type: :fragment, fragment_id: 999_999_999}))

      assert socket.assigns.fragment_not_found
      assert Map.has_key?(socket.assigns, :fragment)
    end
  end
end
