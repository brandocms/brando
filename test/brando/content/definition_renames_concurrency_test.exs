defmodule Brando.Content.DefinitionRenamesConcurrencyTest do
  # brandocms/brando#3844, edge case 2: a value an editor writes under the
  # new key from another connection while the apply moves values. The
  # sandbox shares one connection between processes, so the race needs two
  # real ones: the rows are committed, and every row the test adds is
  # deleted after it.
  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{Block, Blocks, Definitions, Var}
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures
  alias Ecto.Adapters.SQL.Sandbox

  @repo Brando.Repo.repo()

  setup do
    before = last_ids()
    path = Path.join(System.tmp_dir!(), "brando-renames-race-#{System.unique_integer([:positive])}")

    on_exit(fn ->
      File.rm_rf!(path)
      delete_since!(before)
    end)

    %{path: path}
  end

  test "a value written under the new key while the apply holds its locks lands after it, and is kept", %{path: path} do
    {user, page, block, plan} = unboxed(fn -> rename_fixture!(path) end)

    test = self()
    handler = "renames-race-#{System.unique_integer([:positive])}"

    apply =
      Task.async(fn ->
        receive do
          :start -> unboxed(fn -> Definitions.apply(plan, user) end)
        end
      end)

    # The apply stops once it has locked the blocks that hold the old key
    :telemetry.attach(
      handler,
      @repo.config()[:telemetry_prefix] ++ [:query],
      fn _event, _measurements, metadata, apply_pid ->
        if self() == apply_pid and metadata.source == "content_blocks" and metadata.query =~ "FOR UPDATE" do
          send(test, :locked)

          receive do
            :go -> :ok
          end
        end
      end,
      apply.pid
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    send(apply.pid, :start)
    assert_receive :locked, 10_000

    editor =
      Task.async(fn ->
        unboxed(fn ->
          @repo.update_all(from(v in Var, where: v.block_id == ^block.id and v.key == "heading"),
            set: [value: "Typed meanwhile"]
          )
        end)
      end)

    # The editor's write waits for the apply's lock on the values
    refute Task.yield(editor, 500)
    send(apply.pid, :go)

    assert {:ok, _} = Task.await(apply, 30_000)
    assert {1, _} = Task.await(editor, 30_000)

    unboxed(fn ->
      assert [%Var{value: "Typed meanwhile"}] =
               @repo.all(from(v in Var, where: v.block_id == ^block.id and v.key in ["heading", "tagline"]))

      assert [_, _] =
               @repo.all(
                 from(r in Brando.Revisions.Revision,
                   where: r.entry_type == ^to_string(Page) and r.entry_id == ^page.id
                 )
               )
    end)
  end

  # A module whose file renames var tagline to heading; one page's first
  # block holds a value of tagline and an empty heading of its own
  defp rename_fixture!(path) do
    user = Brando.Factory.insert(:random_user)

    module =
      ProposalFixtures.module!(user, "Racer", "<p>{{ tagline }}</p>",
        vars: [%{type: "string", key: "tagline", label: "Tagline", value: "Default tagline"}]
      )

    page = ProposalFixtures.page!(user, "Race", module)
    module.id |> Blocks.list_block_ids_using_module() |> Blocks.sync_blocks(module.id)

    block =
      @repo.one!(
        from(b in Block,
          join: j in Page.Blocks,
          on: j.block_id == b.id,
          where: j.entry_id == ^page.id,
          order_by: j.sequence,
          limit: 1
        )
      )

    @repo.update_all(from(v in Var, where: v.block_id == ^block.id and v.key == "tagline"), set: [value: "Kept words"])
    @repo.insert!(%Var{block_id: block.id, key: "heading", type: :string, label: %{"en" => "Heading"}, value: ""})

    {:ok, _} = Definitions.export(path, user, uids: [module.uid])
    exs = Path.join(path, "content/racer.exs")

    File.write!(
      exs,
      String.replace(
        File.read!(exs),
        ~s(var "tagline", "string" do\n),
        ~s(var "heading", "string" do\n      renamed_from "tagline"\n)
      )
    )

    liquid = Path.join(path, "content/racer.liquid")
    File.write!(liquid, String.replace(File.read!(liquid), "{{ tagline }}", "{{ heading }}"))

    {:ok, bundle} = Definitions.read(path)
    {:ok, plan} = Definitions.plan(bundle, user)
    {user, page, block, plan}
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(@repo, fun)

  # The last id of each table, and of the revisions (keyed by entry)
  defp last_ids do
    unboxed(fn ->
      "SELECT table_name FROM information_schema.columns WHERE table_schema = 'public' AND column_name = 'id' AND data_type IN ('bigint', 'integer')"
      |> @repo.query!()
      |> Map.fetch!(:rows)
      |> List.flatten()
      |> Map.new(fn table -> {table, hd(hd(@repo.query!(~s|SELECT coalesce(max(id), 0) FROM "#{table}"|).rows))} end)
    end)
  end

  # Every row added since `before`; foreign keys aside, as rows reference
  # each other in every direction
  defp delete_since!(before), do: unboxed(fn -> @repo.transaction(fn -> delete_rows!(before) end) end)

  defp delete_rows!(before) do
    @repo.query!("SET LOCAL session_replication_role = replica")
    @repo.query!("DELETE FROM revisions WHERE entry_type = $1 AND entry_id > $2", [to_string(Page), before["pages"]])
    for {table, id} <- before, do: @repo.query!(~s(DELETE FROM "#{table}" WHERE id > $1), [id])
  end
end
