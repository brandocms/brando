defmodule Brando.Content.RenderFailureTest do
  # A stored render in which a block's template fails is not stored: the
  # entry keeps the HTML it had, and the render returns what failed, block by
  # block. The live preview and the editor still show the error in the page.
  use Brando.ConnCase, async: false

  import Brando.EditSessionEditors, only: [rows: 1]
  import ExUnit.CaptureLog
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Blocks
  alias Brando.Content.Definitions
  alias Brando.Content.RenderQueue
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures
  alias Brando.Repo
  alias Brando.Villain.RenderFailure

  @moduletag :capture_log

  setup do
    c = ProposalFixtures.context()
    {:ok, _} = Blocks.render_entry(Page, c.identity.id)
    Map.put(c, :stored, rendered(c.identity))
  end

  describe "a module template that fails" do
    test "to parse: nothing is stored, and each failure names its block", c do
      set_code(c.text_module, "<p>{% if heading %}unclosed</p>")

      assert {:error, {:render_failed, failures}} = Blocks.render_entry(Page, c.identity.id)
      assert rendered(c.identity) == c.stored

      uids = c.identity |> rows() |> Enum.map(& &1.block.uid) |> Enum.sort()
      assert failures |> Enum.map(& &1.block_uid) |> Enum.sort() == uids

      for failure <- failures do
        assert %RenderFailure{kind: :parse, field: :blocks, module_name: "Text", block_type: :module} = failure
        assert failure.module_id == c.text_module.id
        assert failure.module_uid == c.text_module.uid
        assert is_integer(failure.block_id)
        assert is_integer(failure.line)
        assert failure.message =~ ~r/\S/
      end
    end

    test "iterating over nil: nothing is stored", c do
      set_code(c.text_module, "<p>{{ missing_list | sort }}</p>")

      assert {:error, {:render_failed, [failure | _] = failures}} = Blocks.render_entry(Page, c.identity.id)
      assert length(failures) == 3
      assert rendered(c.identity) == c.stored
      assert %RenderFailure{kind: :iterate_over_nil, module_name: "Text", field: :blocks} = failure
      assert failure.message =~ "nil"
    end

    test "at runtime in Liquid: nothing is stored", c do
      set_code(c.text_module, ~s(<p>{{ "x" | no_such_filter }}</p>))

      assert {:error, {:render_failed, [failure | _]}} = Blocks.render_entry(Page, c.identity.id)
      assert rendered(c.identity) == c.stored
      assert %RenderFailure{kind: :render, module_name: "Text"} = failure
      assert failure.message =~ "no_such_filter"
    end

    test "at runtime in HEEx: nothing is stored", c do
      set_code(c.text_module, ~s(<p>{raise "boom in heex"}</p>), :heex)

      assert {:error, {:render_failed, [failure | _]}} = Blocks.render_entry(Page, c.identity.id)
      assert rendered(c.identity) == c.stored
      assert %RenderFailure{kind: :render, module_name: "Text"} = failure
      assert failure.message =~ "boom in heex"
    end

    test "beside blocks that render: nothing is stored, and only the failing block is named", c do
      broken = ProposalFixtures.module!(c.user, "Broken", "<p>{% if %}</p>", [])
      bad = add_block(c.identity, broken, c.user, 3)

      assert {:error, {:render_failed, [failure]}} = Blocks.render_entry(Page, c.identity.id)
      assert rendered(c.identity) == c.stored
      assert failure.block_uid == bad.uid
      assert failure.block_id == bad.id
      assert failure.module_name == "Broken"
    end

    test "inside a container's child: the child is named", c do
      broken = ProposalFixtures.module!(c.user, "Broken", "<p>{% if %}</p>", [])
      child = add_contained_block(c.identity, broken, c.user, 3)

      assert {:error, {:render_failed, [failure]}} = Blocks.render_entry(Page, c.identity.id)
      assert failure.block_uid == child.uid
      assert failure.module_name == "Broken"
    end
  end

  describe "a container template that fails" do
    # Its Liquid runs in the entry's last pass, over every block's output
    test "names the root block that holds it", c do
      {:ok, container} =
        Brando.Content.create_container(
          %{name: "Broken", namespace: "all", help_text: "x", code: "<section>{% if %}{{ content }}</section>"},
          c.user
        )

      block = insert_block(%{"type" => "container", "container_id" => container.id}, c.user, Page.Blocks)
      struct(Page.Blocks, %{entry_id: c.identity.id, block_id: block.id, sequence: 3}) |> Repo.insert!()

      assert {:error, {:render_failed, [failure]}} = Blocks.render_entry(Page, c.identity.id)
      assert rendered(c.identity) == c.stored
      assert %RenderFailure{kind: :parse, block_type: :container, field: :blocks} = failure
      assert failure.block_uid == block.uid
    end
  end

  describe "rendering without storing" do
    test "render_fields/2 returns each field's HTML, or the failures, and stores nothing", c do
      entry = load(c.identity)
      assert {:ok, %{blocks: html}} = Blocks.render_fields(Page, entry)
      assert html =~ "Identity 0"

      set_code(c.text_module, "<p>{% if heading %}unclosed</p>")
      version = row_version(c.identity)

      assert {:error, {:render_failed, [_, _, _]}} = Blocks.render_fields(Page, load(c.identity))
      assert row_version(c.identity) == version
    end

    test "Villain.parse_checked/3 returns the failures, Villain.parse/3 the page with the error in it", c do
      set_code(c.text_module, "<p>{% if heading %}unclosed</p>")
      entry = load(c.identity)

      assert {:error, [%RenderFailure{field: nil} | _]} = Brando.Villain.parse_checked(entry.entry_blocks, entry)
      assert Brando.Villain.parse(entry.entry_blocks, entry) =~ "!!! Error parsing liquex template !!!"
    end
  end

  describe "the live preview" do
    test "still shows the error in the page", c do
      set_code(c.text_module, "<p>{% if heading %}unclosed</p>")
      entry = load(c.identity)

      # As `Brando.LivePreview` renders it
      html = Brando.Villain.parse(entry.entry_blocks, entry, cache_modules: true, annotate_blocks: true)
      assert html =~ "!!! Error parsing liquex template !!!"

      set_code(c.text_module, "<p>{{ missing_list | sort }}</p>")
      html = Brando.Villain.parse(entry.entry_blocks, entry, cache_modules: true, annotate_blocks: true)
      assert html =~ "Liquex template error: trying to iterate over nil collection"
    end
  end

  describe "the render job" do
    test "is cancelled with the failure, which await_refresh lists, and logs it once", c do
      set_code(c.text_module, ~s(<p>{{ "x" | no_such_filter }}</p>))

      log =
        capture_log([level: :error], fn ->
          Oban.Testing.with_testing_mode(:manual, fn ->
            {_, run} = Definitions.track_refresh(fn -> RenderQueue.enqueue(%{schema: Page, entry_id: c.identity.id}) end)
            Oban.drain_queue(queue: :default)

            assert %{rendered: 0, pending: [], timed_out: false, failed: [failure]} =
                     Definitions.await_refresh(run, timeout: 1_000)

            assert %{worker: :render, state: "cancelled", schema: "Brando.Pages.Page"} = failure
            assert failure.entry_id == c.identity.id
            assert failure.error =~ "no_such_filter"
            assert failure.error =~ "Text"

            # Not retried: the template fails the same way every time
            assert [%Oban.Job{state: "cancelled", attempt: 1}] =
                     Repo.all(from(j in Oban.Job, where: j.worker == "Brando.Worker.EntryRenderer"))
          end)
        end)

      assert rendered(c.identity) == c.stored
      assert length(Regex.scan(~r/Rendering .* failed/, log)) == 1
      assert log =~ "Brando.Pages.Page"
      assert log =~ "no_such_filter"
    end
  end

  describe "mix brando.entries.resave" do
    test "keeps the HTML of an entry whose block template fails, and names it and its blocks", c do
      set_code(c.text_module, "<p>{% if heading %}unclosed</p>")

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert {:ok, 0} = Brando.Content.Resave.run(blueprint: "Brando.Pages.Page", reload_caches: false)
        end)

      assert rendered(c.identity) == c.stored
      assert output =~ "failed!"
      assert output =~ ~s(module "Text")
      [first | _] = rows(c.identity)
      assert output =~ first.block.uid
      assert output =~ "keep the HTML they had: a block template failed"
      assert output =~ "page:#{c.identity.id} (Identity)"
    end
  end

  describe "a fragment" do
    setup c do
      fragment = Brando.Factory.insert(:fragment, creator: c.user, key: "shared", parent_key: "site")
      add_block(fragment, c.text_module, c.user, 0, Fragment.Blocks)
      {:ok, _} = Blocks.render_entry(Fragment, fragment.id)
      add_fragment_block(c.naming, fragment, c.user)
      {:ok, _} = Blocks.render_entry(Page, c.naming.id)
      Map.merge(c, %{fragment: fragment, fragment_html: Repo.get!(Fragment, fragment.id).rendered_blocks})
    end

    test "that fails is not stored, and the entries embedding it do not render again", c do
      page_html = rendered(c.naming)
      assert page_html =~ c.fragment_html

      set_code(c.text_module, "<p>{% if heading %}unclosed</p>")

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:error, {:render_failed, [_]}} = Blocks.render_entry(Fragment, c.fragment.id)
        assert [] = all_enqueued(worker: Brando.Worker.EntryRenderer)
      end)

      assert Repo.get!(Fragment, c.fragment.id).rendered_blocks == c.fragment_html
      assert rendered(c.naming) == page_html
    end
  end

  defp set_code(module, code, type \\ :liquid) do
    {1, _} =
      Repo.update_all(from(m in Brando.Content.Module, where: m.id == ^module.id), set: [code: code, type: type])

    :ok
  end

  defp rendered(page), do: Repo.get!(Page, page.id).rendered_blocks

  defp load(page) do
    {:ok, entry} = Brando.Blueprint.EntryQuery.get(Page, page.id)
    entry
  end

  defp row_version(page),
    do: Repo.one(from(p in Page, where: p.id == ^page.id, select: fragment("xmin::text")))

  defp add_block(entry, module, user, sequence, join \\ Page.Blocks) do
    block = insert_block(%{"type" => "module", "module_id" => module.id}, user, join)
    struct(join, %{entry_id: entry.id, block_id: block.id, sequence: sequence}) |> Repo.insert!()
    block
  end

  defp add_contained_block(entry, module, user, sequence) do
    container = insert_block(%{"type" => "container"}, user, Page.Blocks)
    struct(Page.Blocks, %{entry_id: entry.id, block_id: container.id, sequence: sequence}) |> Repo.insert!()

    insert_block(%{"type" => "module", "module_id" => module.id, "parent_id" => container.id}, user, Page.Blocks)
  end

  defp add_fragment_block(entry, fragment, user) do
    block = insert_block(%{"type" => "fragment", "fragment_id" => fragment.id}, user, Page.Blocks)
    struct(Page.Blocks, %{entry_id: entry.id, block_id: block.id, sequence: 3}) |> Repo.insert!()
  end

  defp insert_block(params, user, join) do
    %Brando.Content.Block{}
    |> Brando.Content.Block.recursive_block_changeset(
      Map.merge(%{"uid" => Brando.Utils.generate_uid(), "creator_id" => user.id, "source" => to_string(join)}, params),
      user
    )
    |> Repo.insert!()
  end
end
