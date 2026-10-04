defmodule BrandoAdmin.Components.Form.Block.MissingTargetTest do
  # A block whose module, container or fragment is gone says which one, and
  # offers to delete the block. The id used to print as a literal `#{...}`:
  # HEEx does not interpolate Elixir string syntax.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias BrandoAdmin.Components.Form.Block.Render

  for {flag, key, noun} <- [
        {:module_not_found, :module_id, "module"},
        {:container_not_found, :container_id, "container"},
        {:fragment_not_found, :fragment_id, "fragment"}
      ] do
    test "a missing #{noun} names its id" do
      rendered = Render.render(%{unquote(flag) => true, unquote(key) => 42, myself: nil, __changed__: nil})
      html = rendered_to_string(rendered)

      # A live component's root must be one static tag, or LiveView raises.
      assert %Phoenix.LiveView.Rendered{root: true} = rendered

      assert html =~ "This block uses #{unquote(noun)} #42, which no longer exists."
      assert html =~ ~s(phx-click="delete_block")
      refute html =~ "inspect("
    end
  end
end
