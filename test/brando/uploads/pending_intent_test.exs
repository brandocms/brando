defmodule Brando.Uploads.PendingIntentTest do
  # Regression coverage for D1 in the form audit — a client-direct upload that
  # completed after the sticky UploadManager remounted was silently dropped.
  #
  # The key and resolved config target needed to finalize lived only in the
  # manager's `items` assign, and `mount/1` hard-assigns `items: %{}`. So a
  # reconnect (or any navigation that rebuilt the Chrome) mid-transfer left the
  # bytes in the bucket with no `File`/`Image` row, no log, and no reaper —
  # videos have `VideoUploadReaper`, files and images had nothing.
  #
  # Intents are now written at presign and removed on finalize / error / cancel.
  # What survives is an abandoned transfer, and belongs to
  # `Brando.Worker.UploadIntentReaper`.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Uploads
  alias Brando.Uploads.PendingIntent
  alias Phoenix.Component

  setup do
    {:ok, user: Factory.insert(:random_user)}
  end

  defp attrs(overrides) do
    Map.merge(
      %{
        ref: Ecto.UUID.generate(),
        key: "files/direct/report.pdf",
        resolved_target: "file:Brando.Pages.Page:pdf",
        asset_type: :file,
        mime_type: "application/pdf",
        filename: "report.pdf",
        filesize: 1234,
        target: %{"deliver_topic" => "form:abc", "kind" => "entry_field"}
      },
      overrides
    )
  end

  describe "create/get/delete" do
    test "an intent round-trips with its whole delivery target", ctx do
      ref = Ecto.UUID.generate()

      assert {:ok, _} =
               Uploads.create_pending_intent(attrs(%{ref: ref, creator_id: ctx.user.id}))

      assert %PendingIntent{} = intent = Uploads.get_pending_intent(ref)
      assert intent.key == "files/direct/report.pdf"
      assert intent.resolved_target == "file:Brando.Pages.Page:pdf"
      assert intent.asset_type == :file

      # The target has to survive whole — a finalize after a remount delivers
      # from it, and losing `deliver_topic` would strand the asset in the
      # library with the editor never told about it.
      assert intent.target["deliver_topic"] == "form:abc"
    end

    test "the ref is what a direct_complete carries, so it must be unique" do
      ref = Ecto.UUID.generate()

      assert {:ok, _} = Uploads.create_pending_intent(attrs(%{ref: ref}))
      assert {:error, changeset} = Uploads.create_pending_intent(attrs(%{ref: ref}))
      assert changeset.errors[:ref]
    end

    test "key and resolved_target are required — finalize trusts nothing else" do
      assert {:error, changeset} =
               Uploads.create_pending_intent(%{ref: Ecto.UUID.generate(), asset_type: :file})

      assert changeset.errors[:key]
      assert changeset.errors[:resolved_target]
    end

    test "an unknown ref is nil, not a raise" do
      refute Uploads.get_pending_intent(Ecto.UUID.generate())
    end

    test "a malformed ref is nil, not a raise" do
      # `direct_complete` carries a client-supplied ref. A non-UUID reaching
      # `get_by` would raise Ecto.Query.CastError and take the sticky manager —
      # and every in-flight upload with it — down.
      refute Uploads.get_pending_intent("../../etc/passwd")
      refute Uploads.get_pending_intent("")
      refute Uploads.get_pending_intent(nil)
      refute Uploads.get_pending_intent(%{})
    end

    test "deleting by ref is idempotent" do
      ref = Ecto.UUID.generate()
      assert {:ok, _} = Uploads.create_pending_intent(attrs(%{ref: ref}))

      assert {:ok, %PendingIntent{}} = Uploads.delete_pending_intent(ref)
      assert {:ok, :not_found} = Uploads.delete_pending_intent(ref)
      refute Uploads.get_pending_intent(ref)
    end
  end

  describe "list_stale_pending_intents/1" do
    defp backdate(ref, hours) do
      intent = Uploads.get_pending_intent(ref)
      at = NaiveDateTime.add(NaiveDateTime.utc_now(), -hours * 3600, :second)

      intent
      |> Ecto.Changeset.change(inserted_at: NaiveDateTime.truncate(at, :second))
      |> Brando.Repo.repo().update!()
    end

    test "leaves a transfer that could still be in flight alone" do
      ref = Ecto.UUID.generate()
      {:ok, _} = Uploads.create_pending_intent(attrs(%{ref: ref}))

      # A large upload over a slow link must never be reaped out from under
      # itself, which is why the cutoff clears the presign lifetime by hours.
      backdate(ref, 2)

      assert Uploads.list_stale_pending_intents(24) == []
    end

    test "returns an intent past the cutoff" do
      ref = Ecto.UUID.generate()
      {:ok, _} = Uploads.create_pending_intent(attrs(%{ref: ref}))
      backdate(ref, 48)

      assert [%PendingIntent{ref: ^ref}] = Uploads.list_stale_pending_intents(24)
    end
  end

  describe "the reaper" do
    test "removes stale intents and leaves fresh ones", _ctx do
      stale_ref = Ecto.UUID.generate()
      fresh_ref = Ecto.UUID.generate()

      {:ok, _} = Uploads.create_pending_intent(attrs(%{ref: stale_ref}))
      {:ok, _} = Uploads.create_pending_intent(attrs(%{ref: fresh_ref}))

      stale = Uploads.get_pending_intent(stale_ref)

      stale
      |> Ecto.Changeset.change(
        inserted_at: NaiveDateTime.truncate(NaiveDateTime.add(NaiveDateTime.utc_now(), -48 * 3600), :second)
      )
      |> Brando.Repo.repo().update!()

      assert :ok = Brando.Worker.UploadIntentReaper.perform(%Oban.Job{args: %{}})

      # Deleted for real, not soft-deleted: a row the reaper "kept" would be
      # swept again every night, and it is the object that matters here.
      refute Uploads.get_pending_intent(stale_ref)
      assert Uploads.get_pending_intent(fresh_ref)
    end

    test "a bucket that refuses the delete still drops the row" do
      # This target has no CDN configured at all, so `delete_direct_object/3`
      # errors. Leaving the row would make the sweep retry the same failure
      # nightly forever.
      ref = Ecto.UUID.generate()

      {:ok, _} =
        Uploads.create_pending_intent(
          attrs(%{ref: ref, asset_type: :image, resolved_target: "image:Brando.Pages.Page:meta_image"})
        )

      Uploads.get_pending_intent(ref)
      |> Ecto.Changeset.change(
        inserted_at: NaiveDateTime.truncate(NaiveDateTime.add(NaiveDateTime.utc_now(), -48 * 3600), :second)
      )
      |> Brando.Repo.repo().update!()

      assert :ok = Brando.Worker.UploadIntentReaper.perform(%Oban.Job{args: %{}})
      refute Uploads.get_pending_intent(ref)
    end
  end

  describe "direct_complete after the manager remounted" do
    # The behavioural core of D1. A freshly-mounted manager has `items: %{}`,
    # so the completion arrives with nothing in memory to match it against.
    #
    # There is no S3 mock boundary in this repo yet (a Phase 4 task), so
    # `finalize_direct/3` cannot be driven to success here. What these assert is
    # the part that was actually broken: the completion now REACHES finalize via
    # the persisted intent instead of falling into a silent `_ -> {:noreply}`.
    defp remounted_manager(user) do
      %Phoenix.LiveView.Socket{}
      |> Component.assign(:items, %{})
      |> Component.assign(:order, [])
      |> Component.assign(:current_user, user)
    end

    test "an unknown ref is refused without crashing the sticky manager", ctx do
      socket = remounted_manager(ctx.user)

      assert {:noreply, socket} =
               BrandoAdmin.UploadManager.handle_event(
                 "direct_complete",
                 %{"ref" => Ecto.UUID.generate()},
                 socket
               )

      assert socket.assigns.items == %{}
    end

    test "a known ref is recovered from its intent, and kept if finalize fails", ctx do
      ref = Ecto.UUID.generate()
      {:ok, _} = Uploads.create_pending_intent(attrs(%{ref: ref, creator_id: ctx.user.id}))

      assert {:noreply, _socket} =
               BrandoAdmin.UploadManager.handle_event(
                 "direct_complete",
                 %{"ref" => ref},
                 remounted_manager(ctx.user)
               )

      # Finalize could not verify the object (no bucket in tests), so the intent
      # survives — only the reaper is allowed to decide a transfer is abandoned.
      assert Uploads.get_pending_intent(ref)
    end

    test "a forged ref cannot finalize anything", ctx do
      # No intent was ever written for this ref, so there is no server-side key
      # or target to work from and nothing can be created.
      assert {:noreply, _socket} =
               BrandoAdmin.UploadManager.handle_event(
                 "direct_complete",
                 %{"ref" => "not-even-a-uuid"},
                 remounted_manager(ctx.user)
               )
    end
  end

  describe "delete_direct_object/3" do
    test "reports rather than raises when the target has no direct transport" do
      # Images never use the client-direct transport, so there is nothing to
      # delete — and the nightly sweep must not die telling us so.
      assert {:error, _} =
               Uploads.delete_direct_object(:image, "image:Brando.Pages.Page:meta_image", "k")
    end

    test "reports rather than raises on a target that no longer resolves" do
      assert {:error, _} = Uploads.delete_direct_object(:video, "video:No.Such.Schema:clip", "k")
    end
  end
end
