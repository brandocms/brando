defmodule BrandoAdmin.RenderStoreOrderTest do
  # An editor's save renders the entry inline and stores the HTML with its
  # blocks. A background render of the same entry (a module save's, say)
  # loads the entry, renders and stores. Whichever stores last, the stored
  # HTML is the saved blocks rendered from the newest modules (#3471).
  use Brando.LiveCase

  import Brando.EditSessionEditors
  import Brando.Test.Users

  alias Brando.Content.Blocks
  alias Brando.Pages.Page

  for mode <- [:legacy, :groups] do
    describe "with #{mode} authorization" do
      setup %{conn: conn} do
        c = Brando.ProposalFixtures.context()
        {:ok, _} = Blocks.render_entry(Page, c.identity.id)
        [first | _] = rows(c.identity)
        Map.merge(c, %{conn: editor(conn, unquote(mode)), first: first.block.uid})
      end

      test "a render that loaded the entry before the save renders the saved blocks", c do
        # A module save queues the entry's render, which loads it and renders
        Oban.Testing.with_testing_mode(:manual, fn -> change_module(c) end)
        render = start_held_render(c.identity)

        view = open(c.conn, c.identity)
        type(view, c.first, "<p>Saved by the editor</p>")
        save(view)
        await(fn -> rendered(c.identity) =~ "Saved by the editor" end)

        resume(render)
        assert {:ok, _} = Task.await(render)

        html = rendered(c.identity)
        assert html =~ "Saved by the editor"
        assert html =~ ~s(class="v2")
      end

      test "a render that stored while the save rendered gets another after the save", c do
        view = open(c.conn, c.identity)
        type(view, c.first, "<p>Saved by the editor</p>")
        save_read(view)
        hold = hold_inline_render(view)
        saving = Task.async(fn -> save_write(view) end)
        assert_receive {:held, _}, 5_000

        # The module changes while the save renders from the old one, and
        # its render stores before the save does
        change_module(c)

        assert rendered(c.identity) =~ ~s(class="v2")
        refute rendered(c.identity) =~ "Saved by the editor"

        send(view.pid, {:resume, hold})
        Task.await(saving)
        await(fn -> rendered(c.identity) =~ "Saved by the editor" end)

        html = rendered(c.identity)
        assert html =~ "Saved by the editor"
        assert html =~ ~s(class="v2")
      end
    end
  end

  defp change_module(c) do
    {:ok, _} =
      Brando.Content.update_module(c.text_module.id, %{code: ~s(<div class="v2">{% ref refs.body %}</div>)}, :system)
  end

  defp editor(conn, :legacy), do: conn

  # The page is published: changing it takes the publish grant too
  defp editor(conn, :groups) do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    {conn, _user} = log_in_as(conn, permissions: ~w(brando.pages.read brando.pages.update brando.pages.publish))
    conn
  end

  defp open(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  # A save is two submits: the first collects the blocks, the second writes
  defp save(view) do
    save_read(view)
    save_write(view)
  end

  defp save_read(view) do
    view |> form("#page_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 5_000)
  end

  defp save_write(view), do: view |> form("#page_form_form") |> render_submit()

  defp rendered(page), do: Repo.get!(Page, page.id).rendered_blocks

  # A background render, held once it has loaded the entry and rendered, and
  # before it stores, until `resume/1`
  defp start_held_render(page) do
    test = self()
    id = make_ref()
    :ok = :telemetry.attach(id, [:brando, :villain, :parse_and_render], &__MODULE__.hold_render/4, test)
    on_exit(fn -> :telemetry.detach(id) end)

    task =
      Task.async(fn ->
        Process.put(:render_store_order_hold, true)
        Blocks.render_entry(Page, page.id)
      end)

    pid = task.pid
    assert_receive {:held, ^pid}, 5_000
    task
  end

  defp resume(%Task{pid: pid}), do: send(pid, :resume)

  @doc "The telemetry handler `start_held_render/1` attaches."
  def hold_render(_event, _measurements, _metadata, test) do
    if Process.delete(:render_store_order_hold) do
      send(test, {:held, self()})

      receive do
        :resume -> :ok
      end
    end
  end

  # The view's next render, held until the view is sent `{:resume, ref}`:
  # the save's inline render, which has read the modules
  defp hold_inline_render(view) do
    ref = make_ref()
    armed = :counters.new(1, [])
    :counters.put(armed, 1, 1)
    config = %{test: self(), pid: view.pid, armed: armed, ref: ref}
    :ok = :telemetry.attach(ref, [:brando, :villain, :parse_and_render], &__MODULE__.hold_view_render/4, config)
    on_exit(fn -> :telemetry.detach(ref) end)
    ref
  end

  @doc "The telemetry handler `hold_inline_render/1` attaches."
  def hold_view_render(_event, _measurements, _metadata, %{pid: pid, armed: armed, ref: ref} = config) do
    if self() == pid and :counters.get(armed, 1) == 1 do
      :counters.put(armed, 1, 0)
      send(config.test, {:held, self()})

      receive do
        {:resume, ^ref} -> :ok
      end
    end
  end
end
