defmodule Brando.Content.DefinitionsReleaseReviewTest do
  # Round 2 of brandocms/brando#3612: what the admin's Release changes screen
  # does with a release's definitions. Verify renders the affected entries
  # with them and writes nothing; an apply is a batch that can be kept or
  # reverted; a conflict is settled by keeping the version here or taking the
  # release's.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  @moduletag :capture_log

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{DefinitionApply, DefinitionBatch, Definitions, Module}
  alias Brando.Content.Definitions.Release
  alias Brando.Content.Definitions.Release.{Batches, Entries, Proposed, Verify}
  alias Brando.{Factory, Repo}
  alias Brando.Pages.Page
  alias Ecto.Changeset

  setup do
    c = Brando.ProposalFixtures.context()
    path = Path.join(System.tmp_dir!(), "brando-review-#{System.unique_integer([:positive])}")
    {:ok, _} = Definitions.export(path, c.user, uids: [c.text_module.uid])
    File.rm!(Path.join(path, "modules.lock.json"))
    on_exit(fn -> File.rm_rf!(path) end)
    Verify.clear()
    # Recorded as applied: the release's files equal the database
    assert {:ok, %{adopted: 1}} = Release.plan(path: path, version: "1.0.0")
    Map.put(c, :path, path)
  end

  defp opts(c, extra \\ []), do: Keyword.merge([path: c.path, version: "2.0.0"], extra)

  defp template_path(c), do: Path.join(c.path, "content/text.liquid")

  # The release changes the Text module's template
  defp release!(c, code), do: File.write!(template_path(c), code)

  defp text(c), do: Repo.get!(Module, c.text_module.id)

  defp report!(c, extra \\ []) do
    {:ok, report} = Release.plan(opts(c, Keyword.merge([user: c.user.id], extra)))
    report
  end

  defp manual(fun), do: Oban.Testing.with_testing_mode(:manual, fun)

  defp pages, do: Repo.all(from(p in Page, order_by: p.id, select: {p.id, p.rendered_blocks, p.updated_at}))

  defp snapshot do
    {pages(), Repo.aggregate(Oban.Job, :count), Repo.aggregate(DefinitionApply, :count),
     Repo.all(from(m in Module, select: {m.id, m.code, m.version}))}
  end

  defp await_run(prefix \\ nil) do
    Enum.reduce_while(1..200, nil, fn _, _ ->
      case Verify.get(prefix) do
        %{status: :running} -> Process.sleep(20) && {:cont, nil}
        run -> {:halt, run}
      end
    end)
  end

  describe "the entries a release affects" do
    test "lists each entry that uses a changed module, with what the admin shows", c do
      ids = Entries.module_ids([c.text_module.uid])
      assert ids == %{c.text_module.id => c.text_module.uid}

      entries = Entries.list(ids)
      assert Enum.map(entries, & &1.id) |> Enum.sort() == Enum.sort([c.identity.id, c.naming.id])
      assert [%{schema: Page, modules: [uid]} | _] = entries
      assert uid == c.text_module.uid
      assert %{entries: 2, types: 1} = Entries.counts(entries)
    end
  end

  describe "Verify" do
    test "renders each entry with the release's definitions and writes nothing", c do
      release!(c, "<p class=\"new\">{{ heading }}</p>{% ref refs.body %}")
      report = report!(c)
      assert [%{action: :update}] = Enum.reject(report.items, &(&1.action == :noop))

      entries = Entries.list(Entries.module_ids([c.text_module.uid]))
      before = snapshot()

      manual(fn ->
        {:ok, run} = Verify.start(report, entries)
        assert run.total == 2
        assert %{status: :done, done: 2, results: results} = await_run()

        for entry <- entries do
          assert %{verdict: :changed, changed: 3, failures: []} = results[entry.key]
        end
      end)

      assert snapshot() == before
    end

    test "an entry whose blocks render the same is unchanged", c do
      # Help text only: nothing renders differently
      File.write!(
        Path.join(c.path, "content/text.exs"),
        c.path |> Path.join("content/text.exs") |> File.read!() |> String.replace(~s("Help"), ~s("Other help"))
      )

      report = report!(c)
      assert [%{action: :update, class: :metadata}] = Enum.reject(report.items, &(&1.action == :noop))
      proposed = Proposed.build(report)

      assert %{verdict: :same, changed: 0, failures: []} = Verify.check(Page, c.identity.id, proposed)
    end

    test "a block that fails to render with the release's definitions fails the entry", c do
      release!(c, "<p>{{ heading }}</p>")
      report = report!(c)
      proposed = Proposed.build(report)
      [{id, module}] = Map.to_list(proposed.changed)

      broken = %{module | type: :heex, code: ~S|<p>{String.to_integer("not a number")}</p>|}

      proposed = %{
        proposed
        | changed: %{id => broken},
          modules: Enum.map(proposed.modules, &if(&1.id == id, do: broken, else: &1))
      }

      assert %{verdict: :failed, failures: [failure | _]} = Verify.check(Page, c.identity.id, proposed)
      assert failure.index == 1
      assert failure.module == "Content › Text"
      assert failure.message =~ "not a number" or failure.message =~ "argument"
    end

    test "can be cancelled, and keeps what it found", c do
      release!(c, "<p class=\"new\">{{ heading }}</p>{% ref refs.body %}")
      report = report!(c)
      entries = Entries.list(Entries.module_ids([c.text_module.uid]))

      {:ok, run} = Verify.start(report, entries, delay: 2_000)
      Process.sleep(100)
      cancelled = Verify.cancel()
      assert cancelled.status == :cancelled
      refute Process.alive?(run.pid)
      assert %{status: :cancelled} = Verify.get()
    end

    test "announces its progress", c do
      release!(c, "<p class=\"new\">{{ heading }}</p>{% ref refs.body %}")
      report = report!(c)
      entries = Entries.list(Entries.module_ids([c.text_module.uid]))
      Phoenix.PubSub.subscribe(Brando.pubsub(), Verify.topic())

      {:ok, %{id: id}} = Verify.start(report, entries)
      assert_receive {:release_verify, nil, %{id: ^id, done: 1}}, 2_000
      assert_receive {:release_verify, nil, %{id: ^id, status: :done, done: 2}}, 2_000
    end
  end

  describe "Verify's edges" do
    test "a stored module that fails to render doesn't stop the run", c do
      text(c)
      |> Changeset.change(type: :heex, code: ~S|<p>{String.to_integer("not a number")}</p>|)
      |> Repo.update!()

      release!(c, "<p class=\"fixed\">{{ heading }}</p>{% ref refs.body %}")
      report = report!(c)
      proposed = Proposed.build(report, conflicts: [c.text_module.uid])

      assert %{verdict: :changed} = Verify.check(Page, c.identity.id, proposed)

      entries = Entries.list(Entries.module_ids([c.text_module.uid]))
      {:ok, _} = Verify.start(report, entries, conflicts: [c.text_module.uid])
      assert %{status: :done, done: 2} = await_run()
    end

    test "whitespace between tags that the release changes is a change", c do
      release!(c, "<p>{{ heading }}</p> {% ref refs.body %}")
      report = report!(c)

      assert %{verdict: :changed} = Verify.check(Page, c.identity.id, Proposed.build(report))
    end
  end

  describe "the per-block diff" do
    test "renders each block both ways, and leaves the others alone", c do
      release!(c, "<p class=\"new\">{{ heading }}</p>{% ref refs.body %}")
      report = report!(c)

      assert {:ok, blocks} = Verify.blocks(Page, c.identity.id, Proposed.build(report))
      assert [%{index: 1, state: :changed, module: "Content › Text"} = first, _, _] = blocks
      refute first.before =~ ~s(class="new")
      assert first.after =~ ~s(class="new")
    end
  end

  describe "an apply as a batch" do
    test "records the batch with its release, renders and Activity, and confirms the one before", c do
      release!(c, "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")

      manual(fn ->
        assert {:ok, %{batch_id: batch_id, run: run}} =
                 Release.apply([c.text_module.uid], opts(c, user: c.user.id, wait: false))

        assert %DefinitionBatch{source: :release, release: "2.0.0", run_id: ^run, confirmed_at: nil} =
                 first = Batches.get(batch_id)

        assert first.applied_by_id == c.user.id
        assert [%{"uid" => uid, "action" => "update"}] = first.definitions["items"]
        assert uid == c.text_module.uid
        assert Batches.pending().id == first.id

        assert Repo.one(
                 from(e in Brando.Activity.Event,
                   where: e.schema == ^to_string(DefinitionBatch) and e.entry_id == ^first.id,
                   select: e.user_id
                 )
               ) == c.user.id

        release!(c, "<p class=\"v3\">{{ heading }}</p>{% ref refs.body %}")

        assert {:ok, %{batch_id: second_id}} =
                 Release.apply(:all, opts(c, user: c.user.id, version: "3.0.0", wait: false))

        assert %{confirmed_how: :next_apply, confirmed_by_id: user_id} = Batches.get(batch_id)
        assert user_id == c.user.id
        assert Batches.pending().batch_id == second_id
      end)
    end

    test "Keep confirms it, and it can't be reverted after", c do
      release!(c, "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")

      manual(fn ->
        {:ok, %{batch_id: batch_id}} = Release.apply(:all, opts(c, user: c.user.id, wait: false))
        assert {:ok, %{confirmed_how: :kept}} = Batches.keep(Batches.get(batch_id), c.user)
        assert Batches.pending() == nil
        assert {:error, :kept} = Batches.revert(Batches.get(batch_id), c.user)
      end)
    end

    test "Keep and Revert on a batch another session already settled say so", c do
      release!(c, "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")

      manual(fn ->
        {:ok, %{batch_id: batch_id}} = Release.apply(:all, opts(c, user: c.user.id, wait: false))
        stale = Batches.get(batch_id)
        {:ok, _} = Batches.keep(Batches.get(batch_id), c.user)

        assert {:error, :kept} = Batches.keep(stale, c.user)
        assert {:error, :kept} = Batches.revert(stale, c.user)
        assert %{reverted_at: nil} = Batches.get(batch_id)
      end)
    end

    test "Revert applies again what the apply replaced, and the release waits again", c do
      original = text(c).code
      release!(c, "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")

      manual(fn ->
        {:ok, %{batch_id: batch_id}} = Release.apply(:all, opts(c, user: c.user.id, wait: false))
        assert text(c).code =~ "v2"

        assert {:ok, %{reverted: [%{uid: uid}], conflicts: [], batch: revert, run: run}} =
                 Batches.revert(Batches.get(batch_id), c.user)

        assert uid == c.text_module.uid
        assert text(c).code == original
        assert revert.source == :revert
        assert revert.reverts_batch_id == batch_id
        assert %{reverted_at: %DateTime{}, revert_batch_id: revert_id} = Batches.get(batch_id)
        assert revert_id == revert.batch_id
        assert Batches.pending() == nil
        assert %{pending: [_ | _]} = Definitions.refresh_status(run)

        assert %DefinitionApply{action: :reverted, source: :revert} =
                 Repo.one(from(a in DefinitionApply, order_by: [desc: a.id], limit: 1))

        assert [%{action: :update, state: :changed_in_release}] =
                 report!(c) |> Map.fetch!(:items) |> Enum.reject(&(&1.action == :noop))
      end)
    end

    test "a module edited here after the apply is left as it is, as a conflict", c do
      release!(c, "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")

      manual(fn ->
        {:ok, %{batch_id: batch_id}} = Release.apply(:all, opts(c, user: c.user.id, wait: false))
        editor = Factory.insert(:random_user, name: "Kari Nordmann")
        edited = text(c) |> Changeset.change(code: "<p class=\"edited\">{{ heading }}</p>") |> Repo.update!()
        Brando.Activity.record(:updated, edited, editor, fields: ["code"])

        batch = Batches.get(batch_id)
        assert %{changed_since: [%{uid: uid, edited: %{by: %{id: editor_id}}}]} = Batches.status(batch, c.user)
        assert uid == c.text_module.uid
        assert editor_id == editor.id

        assert {:ok, %{reverted: [], conflicts: [_]}} = Batches.revert(batch, c.user)
        assert text(c).code =~ "edited"
        assert %{reverted_at: %DateTime{}} = Batches.get(batch_id)
      end)
    end
  end

  describe "a conflict" do
    setup c do
      release!(c, "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")
      manual(fn -> {:ok, _} = Release.apply(:all, opts(c, user: c.user.id, wait: false)) end)
      text(c) |> Changeset.change(code: "<p class=\"here\">{{ heading }}</p>") |> Repo.update!()
      release!(c, "<p class=\"v3\">{{ heading }}</p>{% ref refs.body %}")
      assert [%{action: :conflict, state: :changed_in_both}] = Enum.reject(report!(c).items, &(&1.action == :noop))
      :ok
    end

    test "keeping the version here records the release's file as applied, and it waits no more", c do
      assert {:ok, %DefinitionApply{action: :kept}} = Release.keep_here(c.text_module.uid, opts(c, user: c.user.id))
      assert text(c).code =~ "here"
      assert [%{action: :noop, state: :changed_in_admin}] = report!(c).items
    end

    test "taking the release's version replaces the edit, which the apply row keeps", c do
      uid = c.text_module.uid

      manual(fn ->
        assert {:ok, _} = Release.apply([uid], opts(c, user: c.user.id, version: "3.0.0", discard: [uid], wait: false))
      end)

      assert text(c).code =~ "v3"

      assert %DefinitionApply{action: :replaced, previous: %{"code" => previous}} =
               Repo.one(from(a in DefinitionApply, order_by: [desc: a.id], limit: 1))

      assert previous =~ "here"
    end

    test "can't be applied without a choice", c do
      assert {:error, message} = Release.apply(:all, opts(c, user: c.user.id, version: "3.0.0"))
      assert message =~ "nothing was applied"
    end
  end

  describe "who may" do
    test "a superuser may; another account may not, in legacy authorization", c do
      assert :ok = Release.authorize(c.user)
      admin = Factory.insert(:random_user, role: :admin)
      assert {:error, :forbidden} = Release.authorize(admin)
      assert {:error, :forbidden} = Release.authorize(nil)

      release!(c, "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")
      assert {:error, _} = Release.apply(:all, opts(c, user: admin.id))
      assert text(c).code =~ "{{ heading }}"
      refute text(c).code =~ "v2"
    end
  end

  describe "environments" do
    test "batches and verify runs belong to the environment they ran in", c do
      put_test_env(:tenancy_mode, :multi)

      for prefix <- ["tenant_review_staging", "tenant_review_production"] do
        Ecto.Adapters.SQL.query!(Repo.repo(), ~s(CREATE SCHEMA "#{prefix}"))

        for table <-
              ~w(content_modules content_table_templates content_refs content_vars content_blocks
                 content_definition_applies content_definition_batches activity_events) do
          Ecto.Adapters.SQL.query!(
            Repo.repo(),
            ~s|CREATE TABLE "#{prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|
          )
        end
      end

      hero = Path.join(System.tmp_dir!(), "brando-review-tenant-#{System.unique_integer([:positive])}")
      File.mkdir_p!(hero)
      File.write!(Path.join(hero, "hero.exs"), File.read!("test/fixtures/definitions/hero.exs.txt"))
      on_exit(fn -> File.rm_rf!(hero) end)

      Brando.Tenant.with_prefix("tenant_review_staging", fn ->
        assert {:ok, %{batch_id: batch_id}} =
                 Release.apply(:all, path: hero, version: "1.0.0", user: c.user.id, wait: false)

        assert Batches.pending().batch_id == batch_id
        Verify.start(report!(%{c | path: hero}), [])
        assert %{prefix: "tenant_review_staging"} = Verify.get()
      end)

      Brando.Tenant.with_prefix("tenant_review_production", fn ->
        assert Batches.pending() == nil
        assert Verify.get() == nil
        assert Repo.aggregate(Module, :count) == 0
      end)

      Verify.clear("tenant_review_staging")
    end
  end
end
