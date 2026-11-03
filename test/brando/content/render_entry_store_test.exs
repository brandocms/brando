defmodule Brando.Content.RenderEntryStoreTest do
  # A background render (`Blocks.render_entry/2`) loads the entry, renders
  # and stores. A write that stores the entry's blocks meanwhile (a revision
  # activated, a proposal applied) is not stored over: the render renders
  # again from what it stored (#3471). The admin form's save is in
  # `BrandoAdmin.RenderStoreOrderTest`.
  use Brando.ConnCase, async: false

  import Brando.EditSessionEditors, only: [rows: 1]
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Blocks
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.SetBlockText
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Revisions

  setup do
    c = Brando.ProposalFixtures.context()
    {:ok, _} = Blocks.render_entry(Page, c.identity.id)
    [first | _] = rows(c.identity)
    Map.put(c, :first, first.block.uid)
  end

  test "a revision activated while a render runs is what the render stores", c do
    {:ok, _} = Revisions.create_revision(c.identity, c.user)
    set_text(c, "<p>After the revision</p>")
    change_module(c)
    render = start_held_render(c.identity, fn -> :ok end)

    {:ok, _} = Revisions.set_entry_to_revision(Page, c.identity.id, 0, c.user)

    resume(render)
    assert {:ok, _} = Task.await(render)
    html = rendered(c.identity)
    assert html =~ "Identity 0"
    refute html =~ "After the revision"
    assert html =~ ~s(class="v2")
  end

  test "a proposal applied while a render runs is what the render stores", c do
    change_module(c)
    render = start_held_render(c.identity, fn -> :ok end)

    set_text(c, "<p>Proposed</p>")

    resume(render)
    assert {:ok, _} = Task.await(render)
    html = rendered(c.identity)
    assert html =~ "Proposed"
    assert html =~ ~s(class="v2")
  end

  @tag :capture_log
  test "a render that loses to a write every time gives up after five", c do
    test = self()

    # Every render, another write of the row before it stores
    write = fn ->
      send(test, :rendered)
      Repo.update_all(from(p in Page, where: p.id == ^c.identity.id), set: [title: "Written"])
    end

    change_module(c)
    render = start_held_render(c.identity, write)
    resume(render)

    assert {:error, :entry_changed} = Task.await(render)
    for _ <- 1..5, do: assert_received(:rendered)
    refute_received :rendered
    refute rendered(c.identity) =~ ~s(class="v2")
  end

  test "a render that changes nothing writes nothing", c do
    {:ok, _} = Blocks.render_entry(Page, c.identity.id)
    version = row_version(c.identity)

    assert {:ok, _} = Blocks.render_entry(Page, c.identity.id)
    assert row_version(c.identity) == version
  end

  # A module save queues the entry's render, which renders something new
  defp change_module(c) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _} =
        Brando.Content.update_module(c.text_module.id, %{code: ~s(<div class="v2">{% ref refs.body %}</div>)}, :system)
    end)
  end

  defp set_text(c, text) do
    op = %SetBlockText{target: {Page, c.identity.id}, block_uid: c.first, ref: "body", text: text}
    {:ok, proposal} = Proposals.propose([op], c.user)
    {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
    {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)
  end

  defp rendered(page), do: Repo.get!(Page, page.id).rendered_blocks

  defp row_version(page),
    do: Repo.one(from(p in Page, where: p.id == ^page.id, select: fragment("xmin::text")))

  # A background render, held the first time it has loaded the entry and
  # rendered, before it stores, until `resume/1`. `after_render` runs in it
  # after every render.
  defp start_held_render(page, after_render) do
    test = self()
    id = make_ref()
    :ok = :telemetry.attach(id, [:brando, :villain, :parse_and_render], &__MODULE__.handle_render/4, test)
    on_exit(fn -> :telemetry.detach(id) end)

    task =
      Task.async(fn ->
        Process.put(:render_entry_store_hold, true)
        Process.put(:render_entry_store_after, after_render)
        Blocks.render_entry(Page, page.id)
      end)

    pid = task.pid
    assert_receive {:held, ^pid}, 5_000
    task
  end

  defp resume(%Task{pid: pid}), do: send(pid, :resume)

  @doc false
  def handle_render(_event, _measurements, _metadata, test) do
    if Process.delete(:render_entry_store_hold) do
      send(test, {:held, self()})

      receive do
        :resume -> :ok
      end
    end

    if after_render = Process.get(:render_entry_store_after), do: after_render.()
  end
end
