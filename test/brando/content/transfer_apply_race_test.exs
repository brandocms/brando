defmodule Brando.Content.TransferApplyRaceTest do
  # A content transfer against a definition apply that changes a module the
  # transfer's last item uses, each on its own connection (#3923). An import
  # and a recovery lock that module's row before they write its blocks; they
  # must queue behind a running apply before they do, as an entry save does,
  # or the apply, waiting to update that row, and the transfer, waiting to
  # write the block's refs and vars, deadlock. The sandbox shares one
  # connection between processes, so the rows are committed, and every row
  # the test adds is deleted after it: in `public`, and in a site's schema,
  # which is dropped.
  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Brando.Test.Support
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Definitions
  alias Brando.Content.Transfer
  alias Brando.Content.Transfer.Receipt
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Ecto.Adapters.SQL.Sandbox

  @repo Brando.Repo.repo()
  @site "transfer3923"
  @prefix "tenant_transfer3923_production"

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  for prefix <- [nil, @prefix] do
    describe "in #{prefix || "public"}" do
      @describetag prefix: prefix

      setup :fixture

      test "an import of several entries that holds the module's row: the apply waits, and both land", c do
        plan = in_prefix(c, fn -> entry_plan(c) end)
        assert_both_land(c, fn -> Transfer.apply(plan, c.user) end)
      end

      test "an import of several fields that holds the module's row: the apply waits, and both land", c do
        plan = in_prefix(c, fn -> field_plan(c) end)
        assert_both_land(c, fn -> Transfer.apply(plan, c.user) end)
      end

      test "a recovery of several entries that holds the module's row: the apply waits, and both land", c do
        {:ok, receipt} = in_prefix(c, fn -> Transfer.apply(entry_plan(c), c.user) end)
        assert_both_land(c, fn -> Transfer.restore(receipt.id, c.user) end)
      end

      test "a recovery of several fields that holds the module's row: the apply waits, and both land", c do
        {:ok, receipt} = in_prefix(c, fn -> Transfer.apply(field_plan(c), c.user) end)
        assert_both_land(c, fn -> Transfer.restore(receipt.id, c.user) end)
      end

      test "a recovery whose module goes to the trash after its preview read it is refused", c do
        # The import maps the module to another, so the destinations' rows of
        # it are not locked as part of their trees, and it can be trashed
        receipt =
          in_prefix(c, fn ->
            other = ProposalFixtures.module!(c.user, "Other racer", "<p>{{ tagline }}</p>", vars: tagline_vars())
            {:ok, receipt} = Transfer.apply(entry_plan(c, %{"module:#{c.module.id}" => other.id}), c.user)
            receipt
          end)

        recovery = paused(c, fn -> Transfer.restore(receipt.id, c.user) end, &module_read?/1)
        in_prefix(c, fn -> trash!(c.module) end)
        send(recovery.pid, :go)

        # Refused for the module, by its name, not for something else
        assert {:error, message} = Task.await(recovery, 30_000)
        assert message =~ "Racer"
        assert is_nil(in_prefix(c, fn -> Brando.Repo.get!(Receipt, receipt.id).restored_at end))
      end

      test "an import that starts while the apply holds its locks waits for it", c do
        plan = in_prefix(c, fn -> entry_plan(c) end)
        apply = paused(c, fn -> Definitions.apply(c.definitions, c.user) end, &(&1.query =~ "LOCK TABLE"))
        transfer = reporting(c, fn -> Transfer.apply(plan, c.user) end)

        await_blocked!()
        send(apply.pid, :go)

        assert {:ok, _} = Task.await(apply, 30_000)
        # The module it reviewed has changed since
        assert {:error, _} = Task.await(transfer, 30_000)
      end
    end
  end

  # The transfer stops once it holds the module's row; the apply then waits
  # for it, and the transfer writes the blocks
  defp assert_both_land(c, transfer) do
    transfer = paused(c, transfer, &module_row_lock?/1)
    apply = reporting(c, fn -> Definitions.apply(c.definitions, c.user) end)

    await_blocked!()
    send(transfer.pid, :go)

    assert {:ok, %Receipt{}} = Task.await(transfer, 30_000)
    assert {:ok, _} = Task.await(apply, 30_000)
  end

  defp module_row_lock?(%{query: query}), do: query =~ ~s("content_modules") and query =~ "FOR UPDATE"

  # The dependency loader's read of a module, which the preview runs before
  # any lock on it
  defp module_read?(%{query: query}) do
    {:current_stacktrace, stack} = Process.info(self(), :current_stacktrace)
    query =~ ~s("content_modules") and Enum.any?(stack, &match?({Brando.Content.Transfer.Dependencies, :load!, _, _}, &1))
  end

  defp trash!(module),
    do: module |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Brando.Repo.update!()

  # Two sources, the second with a block of the module, and two
  # destinations, the second holding one too (which a recovery puts back),
  # a module with a var, and a definition apply that changes its code
  defp fixture(%{prefix: prefix}) do
    path = Path.join(System.tmp_dir!(), "brando-transfer-apply-#{System.unique_integer([:positive])}")
    before = last_ids()

    if prefix do
      put_test_env(:media_path, Path.join(path, "media"))
      put_test_env(:sites_path, Path.join(path, "sites"))
      put_test_env(:tenant_migrator, Migrator)
      put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
      put_test_env(:environment_schema_cloner, Brando.TenantCloners)
      put_test_env(:tenancy_mode, :multi, global: true)
      Tenant.put_prefix(nil)
    end

    on_exit(fn ->
      if prefix, do: remove_site()
      unboxed(fn -> @repo.delete_all(from(r in Receipt, where: r.actor_id > ^before["users"])) end)
      delete_since!(before)
      File.rm_rf!(path)
    end)

    user = unboxed(fn -> Brando.Factory.insert(:random_user, role: :superuser, avatar: nil) end)
    if prefix, do: unboxed(fn -> create_site!(user) end)

    unboxed(fn -> Tenant.with_prefix(prefix, fn -> content!(prefix, user, path) end) end)
  end

  defp content!(prefix, user, path) do
    module =
      ProposalFixtures.module!(user, "Racer", "<p>{{ tagline }}</p>", vars: tagline_vars())

    [first, second, first_target, second_target] =
      for title <- ["First", "Second", "First target", "Second target"], do: page!(title, user)

    add_block!(second, module, user)
    add_block!(second_target, module, user)

    definitions_path = Path.join(path, "definitions")
    {:ok, _} = Definitions.export(definitions_path, user, uids: [module.uid])
    liquid = Path.join(definitions_path, "content/racer.liquid")
    File.write!(liquid, String.replace(File.read!(liquid), "<p>{{ tagline }}</p>", "<div>{{ tagline }}</div>"))
    {:ok, bundle} = Definitions.read(definitions_path)
    {:ok, definitions} = Definitions.plan(bundle, user)

    %{
      prefix: prefix,
      user: user,
      module: module,
      sources: [first, second],
      targets: [first_target, second_target],
      definitions: definitions
    }
  end

  defp tagline_vars, do: [%{type: "string", key: "tagline", label: "Tagline", value: "Default tagline"}]

  defp entry_plan(c, dependencies \\ %{}) do
    selectors = for page <- c.sources, do: %{schema: Page, id: page.id}
    archive = read!(Transfer.export(selectors, c.user, media: false))

    targets =
      Map.new(Enum.zip(archive.bundle["entries"], c.targets), fn {%{"key" => key}, target} ->
        {key,
         %{"mode" => "update", "id" => target.id, "publication" => "preserve", "attributes" => %{"uri" => target.uri}}}
      end)

    plan!(archive, targets, c.user, dependencies)
  end

  defp field_plan(c) do
    selectors = for page <- c.sources, do: %{schema: Page, id: page.id, fields: ["blocks"]}
    archive = read!(Transfer.export(selectors, c.user))

    targets =
      Map.new(Enum.zip(archive.bundle["fields"], c.targets), fn {%{"key" => key}, target} ->
        {key, %{"schema" => to_string(Page), "id" => target.id, "field" => "blocks", "mode" => "replace"}}
      end)

    plan!(archive, targets, c.user)
  end

  defp read!({:ok, exported}) do
    {:ok, archive} = Transfer.read(exported.binary)
    archive
  end

  defp plan!(archive, targets, user, dependencies \\ %{}) do
    {:ok, plan} = Transfer.preview(archive, targets, user, dependencies: dependencies)
    [] = plan.problems
    plan
  end

  defp page!(title, user) do
    params = Brando.Factory.params_for(:page, title: title, uri: "race-#{System.unique_integer([:positive])}")
    changeset = %Page{} |> Page.changeset(params, user) |> Map.put(:action, :insert)
    {:ok, page} = Pages.create_page(changeset, user)
    page
  end

  defp add_block!(page, module, user) do
    block = %{
      type: :module,
      module_id: module.id,
      source: to_string(Page.Blocks),
      uid: Brando.Utils.generate_uid(),
      vars: [%Brando.Content.Var{type: :string, key: "tagline", label: %{"en" => "Tagline"}, value: "Saved"}]
    }

    {:ok, _} =
      page
      |> Brando.Repo.preload(:entry_blocks, force: true)
      |> Page.changeset(%{}, user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [%{block: block}])
      |> Pages.update_page(user)
  end

  defp create_site!(user) do
    {:ok, _site} =
      Tenant.Setup.create_site(
        %{name: "Transfer race", key: @site, languages: ["en"], default_language: "en", status: :active},
        user,
        seed: false,
        environments: [%{name: "Production", key: "production", live: true}]
      )
  end

  defp remove_site do
    unboxed(fn ->
      %{rows: schemas} =
        @repo.query!("SELECT nspname FROM pg_namespace WHERE starts_with(nspname, $1)", ["tenant_#{@site}_"])

      for [schema] <- schemas, do: Brando.Environments.Schema.drop(schema)
      @repo.delete_all(from(s in Site, where: s.key == @site), prefix: "public")
    end)

    Tenant.Cache.clear()
    Brando.Content.SharedLibrary.Cache.clear()
  end

  defp in_prefix(c, fun), do: unboxed(fn -> Tenant.with_prefix(c.prefix, fun) end)

  # Runs `fun` in `c`'s schema on a connection of its own and stops it after
  # the first query `pause?` matches, until told to go on
  defp paused(c, fun, pause?) do
    test = self()
    handler = "transfer-apply-race-#{System.unique_integer([:positive])}"
    task = Task.async(fn -> receive(do: (:start -> in_prefix(c, fun))) end)

    :telemetry.attach(
      handler,
      @repo.config()[:telemetry_prefix] ++ [:query],
      fn _event, _measurements, metadata, pid ->
        if self() == pid and pause?.(metadata) do
          :telemetry.detach(handler)
          send(test, :paused)
          receive(do: (:go -> :ok))
        end
      end,
      task.pid
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    send(task.pid, :start)
    assert_receive :paused, 10_000
    task
  end

  # Runs `fun` in `c`'s schema on a connection of its own, which it reports
  # to the test
  defp reporting(c, fun) do
    test = self()

    Task.async(fn ->
      in_prefix(c, fn ->
        send(test, {:backend, backend_pid()})
        fun.()
      end)
    end)
  end

  defp backend_pid, do: hd(hd(@repo.query!("SELECT pg_backend_pid()").rows))

  # Until Postgres reports the second connection waiting for another's lock
  defp await_blocked! do
    assert_receive {:backend, pid}, 10_000
    await_blocked!(pid, 500)
  end

  defp await_blocked!(pid, tries) do
    blocked? = unboxed(fn -> hd(hd(@repo.query!("SELECT pg_blocking_pids($1) <> '{}'", [pid]).rows)) end)

    cond do
      blocked? -> :ok
      tries == 0 -> flunk("the second connection never waited for the first")
      true -> Process.sleep(20) && await_blocked!(pid, tries - 1)
    end
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(@repo, fun)

  # The last id of each table in `public`
  defp last_ids do
    unboxed(fn ->
      "SELECT table_name FROM information_schema.columns WHERE table_schema = 'public' AND column_name = 'id' AND data_type IN ('bigint', 'integer')"
      |> @repo.query!()
      |> Map.fetch!(:rows)
      |> List.flatten()
      |> Map.new(fn table -> {table, hd(hd(@repo.query!(~s|SELECT coalesce(max(id), 0) FROM "#{table}"|).rows))} end)
    end)
  end

  # Every row added to `public` since `before`; foreign keys aside, as rows
  # reference each other in every direction
  defp delete_since!(before), do: unboxed(fn -> @repo.transaction(fn -> delete_rows!(before) end) end)

  defp delete_rows!(before) do
    @repo.query!("SET LOCAL session_replication_role = replica")
    @repo.query!("DELETE FROM revisions WHERE entry_type = $1 AND entry_id > $2", [to_string(Page), before["pages"]])
    for {table, id} <- before, do: @repo.query!(~s(DELETE FROM "#{table}" WHERE id > $1), [id])
  end
end
