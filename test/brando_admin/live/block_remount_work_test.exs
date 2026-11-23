defmodule BrandoAdmin.BlockRemountWorkTest do
  # A child block moved to another row mounts again under its new parent,
  # as a new component. Work addressed to it while it moves, an upload
  # finishing into one of its refs or a change typed into one of its fields,
  # stays with the block.
  # Grouped, one at a time: ProposalFixtures.context/0 inserts the pages "identity" and
  # "naming", whose URIs concurrent transactions would wait on
  use Brando.LiveCase, async: true, group: :shared_locks

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block

  setup do
    c = Brando.ProposalFixtures.context()
    c = Brando.ProposalFixtures.multi_context(c)
    row = Brando.ProposalFixtures.root_block!(c, :module, c.projects_module, 2)
    Map.put(c, :row_uid, row.uid)
  end

  defp open(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  defp children(row_uid), do: ~s(.block-children[data-parent-uid="#{row_uid}"])

  defp drop_on_canvas(view, uid, from_uid, old, to_uid, new) do
    view
    |> with_target(cid_of(view, children(from_uid)))
    |> render_hook("reposition", %{
      "uid" => uid,
      "parent_uid" => from_uid,
      "old" => old,
      "new" => new,
      "from" => %{"parentUid" => from_uid},
      "to" => %{"parentUid" => to_uid}
    })
  end

  # Sends the view `message` from inside its handling of the hook `event`,
  # so it arrives while the work that event starts is still under way: in
  # the view's mailbox before the updates that event sends on.
  defp during(view, event, message, fun) do
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      [:phoenix, :live_component, :handle_event, :start],
      &__MODULE__.send_during/4,
      %{pid: view.pid, event: event, message: message}
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end
  end

  @doc false
  def send_during(_name, _measurements, %{event: event}, %{pid: pid, event: event, message: message}) do
    if self() == pid, do: send(pid, message)
  end

  def send_during(_name, _measurements, _metadata, _config), do: :ok

  defp save(view) do
    view |> element("#page_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 5_000)
    view |> element("#page_form_form") |> render_submit()
  end

  defp saved_ref(block_uid, name) do
    Repo.one(
      from(r in Brando.Content.Ref,
        join: b in Block,
        on: b.id == r.block_id,
        where: b.uid == ^block_uid and r.name == ^name
      )
    )
  end

  defp assert_eventually(fun, tries \\ 50) do
    cond do
      fun.() ->
        :ok

      tries == 0 ->
        flunk("condition never held")

      true ->
        Process.sleep(50)
        assert_eventually(fun, tries - 1)
    end
  end

  defp shows_video?(view, row_uid, block_uid, video_id) do
    view
    |> element(~s(#{children(row_uid)} #child_block_form-#{block_uid} input[name$="[video_id]"][value="#{video_id}"]))
    |> has_element?()
  end

  defp video_ready(c, block_uid) do
    clip = saved_ref(block_uid, "clip")
    target = %{"kind" => "block_ref_video", "component_id" => "#{clip.uid}-video", "expected_asset_id" => "none"}
    {:asset_ready, target, c.video}
  end

  describe "an upload into a child block's ref" do
    test "that finishes after the block moved to another row lands in the block", %{conn: conn} = c do
      [_alpha, beta, _gamma] = c.child_uids
      view = open(conn, c.work)

      drop_on_canvas(view, beta, c.multi_uid, 1, c.row_uid, 0)
      render(view)
      send(view.pid, video_ready(c, beta))
      assert_eventually(fn -> shows_video?(view, c.row_uid, beta, c.video.id) end)

      save(view)

      assert_eventually(fn -> saved_ref(beta, "clip").video_id == c.video.id end)
    end

    test "that finishes as the block moves to another row lands in the block", %{conn: conn} = c do
      [_alpha, beta, _gamma] = c.child_uids
      view = open(conn, c.work)
      ready = video_ready(c, beta)
      during(view, "reposition", ready, fn ->
        drop_on_canvas(view, beta, c.multi_uid, 1, c.row_uid, 0)
      end)

      # in the block's form where it went
      assert_eventually(fn -> shows_video?(view, c.row_uid, beta, c.video.id) end)
      save(view)

      assert_eventually(fn -> saved_ref(beta, "clip").video_id == c.video.id end)
    end
  end
end
