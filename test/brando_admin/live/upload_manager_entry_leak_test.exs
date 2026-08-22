defmodule BrandoAdmin.UploadManagerEntryLeakTest do
  @moduledoc """
  Pins the guard that keeps the sticky manager's `allow_upload` config from
  silently filling up and then refusing every further file.

  ## The defect

  A change event carries `serializeUploads/1` — *every* file still tracked on
  the input, not just the ones awaiting preflight — and `Channel`'s
  `maybe_update_uploads/2` feeds that straight into
  `UploadConfig.put_entries/2`, which mints a fresh entry for any ref it does
  not currently hold. A file is untracked only once the browser has processed
  the reply to its final progress push, and the manager frees the next transfer
  slot from `consume_and_deliver/3` — inside that same round trip. So the
  change that starts the next file still carries the file just consumed, and
  the entry the server dropped comes straight back: never preflighted, no
  upload channel behind it, never done. Nothing will ever consume or cancel it,
  and it holds one of the config's `max_entries` slots for the life of the page.

  Past that limit `Phoenix.LiveView.Upload.generate_preflight_response/4` caps
  the refs it answers at `i < conf.max_entries` and omits the rest — no error,
  no entry token. Under `auto_upload: true` the client cancels a tokenless
  entry without telling the server, so the file is never uploaded: no error
  item, nothing in the log, and the source's placeholder waits forever.

  That is why the failure reads as intermittent rather than broken. Measured
  against the unfixed code in a browser, a batch of twelve left nine ghosts
  behind — only the last `max_concurrent_transfers` group was cleaned up — so a
  page uploaded fine until the ghosts reached twenty and then stopped dead,
  mid-batch, with nothing to show for it.

  ## Modelling the browser

  Passing the `%Phoenix.LiveViewTest.Upload{}` handle as a change event's value
  makes `ClientProxy` attach its entries as the event's `"uploads"` payload —
  the same shape `serializeUploads/1` produces, and the only part of the client
  that matters here. Re-sending the handle after its file has been consumed is
  the resurrection, verbatim.

  The negative control matters as much as the leak: a guard that cancels too
  eagerly would break the *first* upload rather than the twenty-first, and both
  read as "uploads are broken" from the outside.
  """

  use Brando.LiveCase

  @fixture Path.expand("../../fixtures/sample.jpg", __DIR__)
  @queue_form "form#brando-upload-manager-queue-form"

  setup %{current_user: user} do
    {:ok, page: Factory.insert(:page, creator: user)}
  end

  test "a consumed upload is not resurrected by the change that starts the next file", %{
    conn: conn,
    page: page
  } do
    manager = mount_manager(conn, page)
    ref = intake(manager, "sample.jpg")
    name = "#{ref}::sample.jpg"

    upload = file_input(manager, @queue_form, :queue, [file(name)])
    render_upload(upload, name)

    assert %{status: status} = items(manager)[ref]
    assert status in [:processing, :done], "the upload never completed: #{inspect(status)}"
    assert entry_refs(manager) == [], "fixture problem: the entry was not consumed"

    # What the browser sends as it hands the next file over: the consumed file
    # is still tracked, so it rides along and the server re-creates its entry.
    resend(manager, upload)

    assert entry_refs(manager) == [],
           "a consumed upload left an entry behind — after #{max_entries(manager)} of these, " <>
             "every further file is dropped with no error and no log line"
  end

  test "an entry for a file still queued is left alone", %{conn: conn, page: page} do
    manager = mount_manager(conn, page)
    ref = intake(manager, "queued.jpg")
    name = "#{ref}::queued.jpg"

    upload = file_input(manager, @queue_form, :queue, [file(name)])

    # Registers the entry without preflighting it — the same state a
    # resurrected entry is in, distinguished only by its item still being
    # `:queued` rather than finished or dismissed.
    resend(manager, upload)

    assert %{status: :queued} = items(manager)[ref]

    assert entry_refs(manager) != [],
           "validate cancelled a live upload — this breaks every file, not just the twenty-first"
  end

  test "entries do not accumulate across a run of uploads", %{conn: conn, page: page} do
    manager = mount_manager(conn, page)

    for n <- 1..3 do
      filename = "run-#{n}.jpg"
      ref = intake(manager, filename)
      name = "#{ref}::#{filename}"

      upload = file_input(manager, @queue_form, :queue, [file(name)])
      render_upload(upload, name)
      resend(manager, upload)

      assert entry_refs(manager) == [],
             "entries survived upload #{n} — the count only ever grows from here"
    end
  end

  ## Helpers

  defp mount_manager(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    find_live_child(view, "brando-upload-manager-lv")
  end

  defp file(name), do: %{name: name, content: File.read!(@fixture), type: "image/jpeg"}

  # Intake is what mints the ref and the drawer item; the JS bridge tags the
  # file "<ref>::<name>" so the manager can pair entry to item.
  defp intake(manager, filename) do
    before = manager |> items() |> Map.keys() |> MapSet.new()

    render_hook(manager, "intake", %{
      "files" => [%{"index" => 0, "name" => filename, "size" => 1_000, "type" => "image/jpeg"}],
      "target" => %{
        "kind" => "entry_field",
        "field" => "meta_image",
        "asset_type" => "image",
        "config_target" => "default",
        "deliver_topic" => "form:#{Ecto.UUID.generate()}"
      }
    })

    [ref] =
      manager
      |> items()
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.difference(before)
      |> MapSet.to_list()

    ref
  end

  # A change on the queue form carrying the handle's entries — `ClientProxy`
  # turns that into the event's "uploads" payload, which is what
  # `maybe_update_uploads/2` re-registers.
  defp resend(manager, upload) do
    manager |> element(@queue_form) |> render_change(upload)
  end

  defp queue_config(manager), do: :sys.get_state(manager.pid).socket.assigns.uploads.queue
  defp entry_refs(manager), do: manager |> queue_config() |> Map.fetch!(:entries) |> Enum.map(& &1.ref)
  defp max_entries(manager), do: manager |> queue_config() |> Map.fetch!(:max_entries)
  defp items(manager), do: :sys.get_state(manager.pid).socket.assigns.items
end
