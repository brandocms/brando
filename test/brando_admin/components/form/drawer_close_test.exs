defmodule BrandoAdmin.Components.Form.DrawerCloseTest do
  # Regression coverage for D7 in the form audit.
  #
  # (a) Closing the image drawer re-queued Oban processing whenever the image
  #     was not yet `:processed`, regardless of what the user had actually
  #     edited. That gate is wrong in both directions: a focal-point change on
  #     an already-processed image (the drawer renders `FocalPoint` bound to
  #     this very form) got NO re-queue, leaving every crop stale — while an
  #     alt-text edit on an unprocessed image restarted a pass that was already
  #     running, and `queue_processing/4` deletes matching jobs before
  #     inserting, so the in-flight job's row went with it.
  #
  # (b) `entry_field_upload_complete` forced `editing_*?` to false. An upload
  #     started inside a drawer leaves that drawer OPEN, and
  #     `assign_drawer_recovery_state/1` gates on exactly those flags — so the
  #     drawer's recovery snapshot was dropped mid-edit, and a save was let
  #     through while the image was still processing, which is precisely what
  #     the guard exists to prevent.
  #
  #     The flag was being cleared there as a workaround for a different bug:
  #     `reset_image_field` / `reset_file_field` closed their drawer without
  #     clearing it, stranding the main save behind "close the drawer first"
  #     with no drawer left to close. (`reset_video_field` always got this
  #     right, which is what made the pair look deliberate.)
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 1]

  alias Brando.Factory
  alias Brando.Images.Processing
  alias BrandoAdmin.Components.Form
  alias Ecto.Changeset
  alias Phoenix.Component

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    {:ok, user: user, page: page}
  end

  defp form_socket(ctx, extra) do
    socket =
      %Phoenix.LiveView.Socket{}
      |> Component.assign(:form, to_form(Changeset.change(ctx.page)))
      |> Component.assign(:entry, ctx.page)
      |> Component.assign(:schema, Brando.Pages.Page)
      |> Component.assign(:singular, "page")
      |> Component.assign(:current_user, ctx.user)
      |> Component.assign(:processing_images, [])
      |> Component.assign(:editing_image?, false)
      |> Component.assign(:editing_video?, false)
      |> Component.assign(:editing_file?, false)
      |> Component.assign(:edit_image, nil)
      |> Component.assign(:edit_video, nil)
      |> Component.assign(:edit_file, nil)
      |> Component.assign(:image_changeset, nil)
      |> Component.assign(:video_changeset, nil)
      |> Component.assign(:file_changeset, nil)

    Component.assign(socket, extra)
  end

  describe "(b) upload completion keeps the drawer's own state truthful" do
    test "an upload into an open image drawer leaves it open and recoverable", ctx do
      image = Factory.insert(:image, creator: ctx.user)

      socket =
        form_socket(ctx, %{
          editing_image?: true,
          edit_image: %{
            id: nil,
            path: [],
            field: :meta_image,
            relation_field: :meta_image_id,
            image: nil,
            schema: Brando.Pages.Page
          }
        })

      assert {:ok, socket} =
               Form.update(
                 %{
                   event: "entry_field_upload_complete",
                   asset_type: :image,
                   field: :meta_image,
                   path: [],
                   asset: image
                 },
                 socket
               )

      # The drawer really is still open — saying otherwise let the entry save
      # while the image was still being processed.
      assert socket.assigns.editing_image?

      # ...and because it is open, the recovery snapshot points at the new image
      # instead of being blanked.
      assert socket.assigns.editing_drawer_type == "image"
      assert socket.assigns.editing_resource_id == image.id
      assert socket.assigns.editing_field == "meta_image"
    end

    test "an upload with no drawer open reports no drawer to recover", ctx do
      image = Factory.insert(:image, creator: ctx.user)

      socket =
        form_socket(ctx, %{
          editing_image?: false,
          edit_image: %{id: nil, path: [], field: :meta_image, relation_field: :meta_image_id, image: nil}
        })

      assert {:ok, socket} =
               Form.update(
                 %{
                   event: "entry_field_upload_complete",
                   asset_type: :image,
                   field: :meta_image,
                   path: [],
                   asset: image
                 },
                 socket
               )

      refute socket.assigns.editing_image?
      assert socket.assigns.editing_drawer_type == nil
    end
  end

  describe "(b) resetting a field closes its drawer AND lowers the guard" do
    test "reset_image_field clears editing_image?", ctx do
      image = Factory.insert(:image, creator: ctx.user)

      socket =
        form_socket(ctx, %{
          editing_image?: true,
          edit_image: %{
            id: image.id,
            path: [],
            field: :meta_image,
            relation_field: :meta_image_id,
            image: image
          }
        })

      assert {:noreply, socket} = Form.handle_event("reset_image_field", %{}, socket)

      # Without this the entry can never be saved again: the JS closed the
      # drawer, so there is nothing left to "close before saving".
      refute socket.assigns.editing_image?
      assert socket.assigns.editing_drawer_type == nil
    end

    # `reset_file_field` received the identical fix; Page has no file asset to
    # drive it through here, and `reset_video_field` already did it correctly.
  end

  describe "(a) processing_queued?/1" do
    # Oban runs `testing: :inline` here, so `queue_processing/4` would execute
    # the job rather than leave it queued. Insert the row directly to get the
    # state the drawer actually has to detect.
    defp queue_job(image, user, field_full_path \\ []) do
      %{
        image_id: image.id,
        config_target: image.config_target,
        user_id: user.id,
        field_full_path: field_full_path,
        silent: false
      }
      |> Brando.Worker.ImageProcessor.new()
      |> Brando.Repo.repo().insert!()
    end

    test "is false when nothing is queued for the image", ctx do
      image = Factory.insert(:image, creator: ctx.user)

      refute Processing.processing_queued?(image)
    end

    test "is true once a pass is queued for that image", ctx do
      image = Factory.insert(:image, creator: ctx.user)
      queue_job(image, ctx.user)

      assert Processing.processing_queued?(image)
    end

    test "does not confuse one image's queued pass for another's", ctx do
      image = Factory.insert(:image, creator: ctx.user)
      other = Factory.insert(:image, creator: ctx.user)
      queue_job(image, ctx.user)

      refute Processing.processing_queued?(other)
    end

    test "matches regardless of the field path the job was queued under", ctx do
      # The drawer asks "is this image already being processed", not "is it
      # being processed for this exact field" — a second pass over the same
      # derivative files is the thing being avoided.
      image = Factory.insert(:image, creator: ctx.user)
      queue_job(image, ctx.user, [:items, 0, :cover])

      assert Processing.processing_queued?(image)
    end

    test "ignores a finished pass", ctx do
      image = Factory.insert(:image, creator: ctx.user)

      image
      |> queue_job(ctx.user)
      |> Ecto.Changeset.change(state: "completed")
      |> Brando.Repo.repo().update!()

      refute Processing.processing_queued?(image)
    end

    test "an image with no id is never considered queued" do
      refute Processing.processing_queued?(%Brando.Images.Image{})
    end
  end
end
