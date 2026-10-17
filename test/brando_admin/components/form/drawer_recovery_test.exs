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
  alias Phoenix.Component

  setup do
    user = Factory.insert(:random_user)
    image = Factory.insert(:image, creator: user)
    {:ok, user: user, image: image}
  end

  defp socket(entry \\ %Brando.Pages.Page{}) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:id, "page_form")
    |> Component.assign(:form, Component.to_form(Changeset.change(entry)))
    |> Component.assign(:editing_image?, false)
    |> Component.assign(:editing_video?, false)
    |> Component.assign(:editing_file?, false)
    |> Component.assign(:edit_image, nil)
    |> Component.assign(:edit_video, nil)
    |> Component.assign(:edit_file, nil)
    |> Component.assign(:image_changeset, nil)
    |> Component.assign(:video_changeset, nil)
    |> Component.assign(:file_changeset, nil)
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

    # Recovery state from before the texts were translated is a plain string;
    # it lands under the default language.
    assert Changeset.get_field(changeset, :title) == %{"en" => "typed caption"}
    assert Changeset.get_field(changeset, :credits) == %{"en" => "typed credits"}

    # They must be *changes*, not merely applied into data — a value sitting in
    # `data` never reaches SQL, which is the single mistake behind most of this
    # audit's findings.
    assert changeset.changes.title == %{"en" => "typed caption"}
    assert changeset.changes.credits == %{"en" => "typed credits"}
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

    assert changeset.changes.title == %{"en" => "ok"}
    refute Map.has_key?(changeset.changes, :creator_id)
    refute Map.has_key?(changeset.changes, :path)
  end

  # The recovery form is in the page, so its params are the browser's: a
  # field, schema, path or id that names nothing leaves the drawer closed.
  test "recovery params that name nothing leave the drawer closed", %{image: image} do
    unknown = "no_such_name_#{System.unique_integer([:positive])}"

    for {key, value} <- [
          {"field", unknown},
          # Existing atoms that name no asset field the drawer opens for
          {"field", "inserted_at"},
          {"field", "title"},
          {"field", "image"},
          {"schema", unknown},
          {"schema", "Elixir.String"},
          {"resource_id", "9223372036854775808"},
          {"resource_id", "0"},
          {"path", Jason.encode!([unknown])},
          {"path", Jason.encode!(["vars", -1])},
          {"path", Jason.encode!([true])},
          {"field", nil},
          {"resource_id", "1x"},
          {"resource_id", 1}
        ] do
      params = put_in(drawer_params(image, "{}"), ["drawer", key], value)

      assert {:noreply, socket} = Form.handle_event("recover_drawer_state", params, socket()),
             "failed for #{key}: #{inspect(value)}"

      refute socket.assigns.editing_image?
    end
  end

  # The drawer's type has to match the field's: an image field does not
  # restore a video or file drawer.
  test "a drawer whose type does not match the field stays closed", %{user: user} do
    video = Factory.insert(:video, creator: user)
    file = Brando.Repo.insert!(%Brando.Files.File{filename: "fixture.txt", creator_id: user.id})

    for {type, resource} <- [{"video", video}, {"file", file}] do
      params = put_in(drawer_params(resource, "{}"), ["drawer", "type"], type)

      assert {:noreply, socket} = Form.handle_event("recover_drawer_state", params, socket())
      refute socket.assigns.editing_video?
      refute socket.assigns.editing_file?
    end
  end

  # A field in a subform row has the row's index in its path.
  test "a recovered drawer keeps its path", %{image: image} do
    article = %Brando.SyncTest.Article{items: [%Brando.SyncTest.ArticleItem{}]}

    params =
      drawer_params(image, "{}")
      |> put_in(["drawer", "path"], Jason.encode!(["items", 0]))
      |> put_in(["drawer", "field"], "cover")
      |> put_in(["drawer", "schema"], to_string(Brando.SyncTest.ArticleItem))

    assert {:noreply, socket} = Form.handle_event("recover_drawer_state", params, socket(article))
    assert socket.assigns.edit_image.path == [:items, 0]
    assert socket.assigns.edit_image.field == :cover
    assert socket.assigns.edit_image.schema == Brando.SyncTest.ArticleItem
  end

  # The drawer commits a pick to `<field>_id` at its path in this form, so a
  # field the form does not hold there leaves the drawer closed.
  test "a drawer for a field the form does not hold at its path stays closed", %{image: image} do
    for changes <- [
          %{"schema" => to_string(Brando.SyncTest.ArticleAuthor), "field" => "portrait"},
          %{"path" => Jason.encode!(["title"])},
          %{"path" => Jason.encode!(["vars", 0])}
        ] do
      params = Map.update!(drawer_params(image, "{}"), "drawer", &Map.merge(&1, changes))

      assert {:noreply, socket} = Form.handle_event("recover_drawer_state", params, socket()),
             "failed for #{inspect(changes)}"

      refute socket.assigns.editing_image?
    end
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
