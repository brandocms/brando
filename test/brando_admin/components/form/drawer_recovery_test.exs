defmodule BrandoAdmin.Components.Form.DrawerRecoveryTest do
  # Regression coverage for C2 — edits made inside an open asset drawer were
  # lost on reconnect.
  #
  # This is a chicken-and-egg problem rather than missing plumbing. The drawer's
  # edit form is `:if={@image_changeset}`-gated, so when the process dies it
  # exists in neither the old nor the new DOM at the moment LiveView runs its
  # recovery diff — and LiveView can only recover forms it can see.
  # `recover_drawer_state` restored *which* asset was being edited, via the
  # always-rendered `#{@id}-drawer-recovery` form, but nothing inside it: the
  # caption, credits and alt text a user had typed were gone.
  #
  # The fix carries those pending values on the always-rendered form and replays
  # them onto the freshly loaded resource. These tests drive the real
  # `recover_drawer_state` handler.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias BrandoAdmin.Components.Form
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)
    image = Factory.insert(:image, creator: user)
    {:ok, user: user, image: image}
  end

  defp socket do
    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(:id, "page_form")
    |> Phoenix.Component.assign(:editing_image?, false)
    |> Phoenix.Component.assign(:editing_video?, false)
    |> Phoenix.Component.assign(:editing_file?, false)
    |> Phoenix.Component.assign(:edit_image, nil)
    |> Phoenix.Component.assign(:edit_video, nil)
    |> Phoenix.Component.assign(:edit_file, nil)
    |> Phoenix.Component.assign(:image_changeset, nil)
    |> Phoenix.Component.assign(:video_changeset, nil)
    |> Phoenix.Component.assign(:file_changeset, nil)
  end

  defp drawer_params(image, changes) do
    %{
      "drawer" => %{
        "type" => "image",
        "resource_id" => to_string(image.id),
        "field" => "meta_image",
        "path" => Jason.encode!([]),
        "schema" => to_string(Brando.Pages.Page),
        "form_id" => "page_form",
        "changes" => changes
      }
    }
  end

  test "replays in-progress drawer edits onto the reloaded image", %{image: image} do
    params =
      drawer_params(
        image,
        Jason.encode!(%{"title" => "typed caption", "credits" => "typed credits"})
      )

    assert {:noreply, socket} = Form.handle_event("recover_drawer_state", params, socket())

    changeset = socket.assigns.image_changeset

    assert Changeset.get_field(changeset, :title) == "typed caption"
    assert Changeset.get_field(changeset, :credits) == "typed credits"

    # They must be *changes*, not merely applied into data — a value sitting in
    # `data` never reaches SQL, which is the single mistake behind most of this
    # audit's findings.
    assert changeset.changes.title == "typed caption"
    assert changeset.changes.credits == "typed credits"
  end

  test "the drawer still restores when there were no pending edits", %{image: image} do
    assert {:noreply, socket} =
             Form.handle_event("recover_drawer_state", drawer_params(image, "{}"), socket())

    assert socket.assigns.editing_image?
    assert socket.assigns.edit_image.id == image.id
    assert socket.assigns.image_changeset.changes == %{}
  end

  test "a missing or malformed changes payload does not break recovery", %{image: image} do
    for changes <- [nil, "", "not json", "[1,2,3]"] do
      params = drawer_params(image, changes)

      assert {:noreply, socket} = Form.handle_event("recover_drawer_state", params, socket()),
             "failed for #{inspect(changes)}"

      assert socket.assigns.editing_image?
      assert socket.assigns.image_changeset.changes == %{}
    end
  end

  test "only the drawer's own fields are replayed", %{image: image} do
    # The payload is a hidden input — hand-editable before submit. Anything
    # outside the drawer's editable field set must not reach the changeset.
    params =
      drawer_params(
        image,
        Jason.encode!(%{"title" => "ok", "creator_id" => "999999", "path" => "/etc/passwd"})
      )

    assert {:noreply, socket} = Form.handle_event("recover_drawer_state", params, socket())

    changeset = socket.assigns.image_changeset

    assert changeset.changes.title == "ok"
    refute Map.has_key?(changeset.changes, :creator_id)
    refute Map.has_key?(changeset.changes, :path)
  end

  describe "unrecoverable drawer state" do
    setup do
      # config/test.exs pins the logger at :error, which would filter the
      # warning under test before capture_log ever sees it.
      previous = Logger.level()
      Logger.configure(level: :warning)
      on_exit(fn -> Logger.configure(level: previous) end)
      :ok
    end

    test "an open drawer with no resource_id is reported, not silently dropped" do
      params = %{"drawer" => %{"type" => "image", "resource_id" => "", "changes" => "{}"}}

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:noreply, _socket} = Form.handle_event("recover_drawer_state", params, socket())
        end)

      assert log =~ "could not recover an open image drawer"
    end

    test "no drawer open stays silent" do
      params = %{"drawer" => %{"type" => "", "resource_id" => "", "changes" => "{}"}}

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:noreply, socket} = Form.handle_event("recover_drawer_state", params, socket())
          refute socket.assigns.editing_image?
        end)

      refute log =~ "could not recover"
    end
  end
end
