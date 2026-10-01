defmodule BrandoAdmin.Components.Form.DraftRecoveryBadgeTest do
  # The header's "Recovery copies (N)" counts copies still waiting for a
  # decision; dismissed ones don't call for attention.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias BrandoAdmin.Components.Form.DraftRecovery

  defp render_with(candidates, open? \\ false) do
    state = %{
      candidates: candidates,
      open?: open?,
      status: :ready,
      checksum: "a",
      baseline: "a",
      selected: nil,
      error: nil,
      compatible?: false,
      preview: [],
      issues: []
    }

    %{id: "draft", state: state, target: nil, entry_id: 1, __changed__: nil}
    |> DraftRecovery.render()
    |> rendered_to_string()
  end

  defp copy(dismissed_at),
    do: %{id: Ecto.UUID.generate(), dismissed_at: dismissed_at, payload: %{}, updated_at: DateTime.utc_now()}

  test "counts only copies that haven't been dismissed" do
    html = render_with([copy(nil), copy(DateTime.utc_now()), copy(DateTime.utc_now())])
    assert html =~ "Recovery copies (1)"
  end

  test "no badge when every copy is dismissed, but the copies stay reachable" do
    html = render_with([copy(DateTime.utc_now()), copy(DateTime.utc_now())])
    refute html =~ "Recovery copies ("
    assert html =~ ~s(phx-click="draft_open")
  end

  test "no button without any copies" do
    refute render_with([]) =~ ~s(phx-click="draft_open")
  end
end
