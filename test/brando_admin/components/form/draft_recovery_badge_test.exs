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

  describe "save state" do
    alias BrandoAdmin.Components.Form.DraftRecovery

    defp state(attrs), do: Map.merge(%{status: :ready, checksum: "a", baseline: "a"}, attrs)

    test "a clean editor says when the entry was saved" do
      assert DraftRecovery.save_state(state(%{})) == "clean"
      assert DraftRecovery.save_label(state(%{}), ~U[2026-09-28 16:40:12Z]) =~ "Saved"
      assert DraftRecovery.save_label(state(%{}), nil) == "Not saved yet"
    end

    test "edits, saved to recovery storage or not, are unsaved changes" do
      assert DraftRecovery.save_state(state(%{status: :saving})) == "dirty"
      assert DraftRecovery.save_state(state(%{checksum: "b"})) == "dirty"
      assert DraftRecovery.save_label(state(%{checksum: "b"}), ~U[2026-09-28 16:40:12Z]) == "Unsaved changes"
    end

    test "a recovery error is shown in full" do
      assert DraftRecovery.save_state(state(%{status: :error})) == "error"
      assert DraftRecovery.save_label(state(%{status: :error}), nil) =~ "keep this editor open"
    end

    test "the status part keeps the recovery status for screen readers and tests" do
      html =
        %{
          id: "draft",
          part: :status,
          state: state(%{checksum: "b", saved_at: ~U[2026-09-28 16:40:12Z], candidates: [], open?: false}),
          saved_at: nil,
          target: nil,
          entry_id: 1,
          __changed__: nil
        }
        |> DraftRecovery.render()
        |> rendered_to_string()

      assert html =~ ~s(data-state="dirty")
      assert html =~ "Unsaved changes"
      assert html =~ ~r/data-testid="draft-status"[^>]*>Recovery copy saved at/
      refute html =~ "draft-recovery-notice"
    end
  end
end
