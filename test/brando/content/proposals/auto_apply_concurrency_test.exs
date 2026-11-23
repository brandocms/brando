defmodule Brando.Content.Proposals.AutoApplyConcurrencyTest do
  # An automatic apply (`Brando.Content.Proposals.AutoApply`) against the
  # connection's setting, revocation, the endpoint's switch and the person's
  # discard, on real connections with commits between them: outside the
  # sandbox, so the locks are real. The apply stops at a query until the
  # test lets it go on.
  use ExUnit.Case, async: false

  import Brando.MCPHelpers, only: [enable_two_factor: 1, switch!: 2]
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.AutoApply
  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Proposals.Receipt
  alias Brando.Content.Proposals.Record
  alias Brando.MCP
  alias Brando.MCP.Grant
  alias Brando.MCP.Setting
  alias Brando.SyncTest.Article
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @handler __MODULE__

  setup do
    tenant = MCP.tenant(nil, nil)
    slug = "auto-apply-#{System.unique_integer([:positive])}"

    {user, module, source, setting} =
      Sandbox.unboxed_run(Repo, fn ->
        setting = Repo.one(from(s in Setting, where: is_nil(s.site_id) and is_nil(s.environment_id)))
        user = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil, config: %Brando.Users.UserConfig{})
        enable_two_factor(user)
        switch!(tenant, true)

        {:ok, module} =
          Brando.Content.create_module(
            Brando.Factory.params_for(:module,
              name: %{"en" => "Text"},
              namespace: %{"en" => "Content"},
              help_text: %{},
              code: "{% ref refs.body %}",
              refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: ""}}}]
            ),
            user
          )

        {:ok, source} =
          Brando.SyncTest.create_article(%{title: "Tittel", slug: slug, language: "no", status: "published"}, user)

        Brando.TranslationFixtures.add_block(source, module, user, "<p>Første avsnitt</p>", 0)
        {user, module, source, setting}
      end)

    on_exit(fn ->
      :telemetry.detach(@handler)
      Sandbox.unboxed_run(Repo, fn -> clean_up(user, module, tenant, setting) end)
    end)

    %{tenant: tenant, user: user, source: source}
  end

  # What the setup and the tests wrote, which no sandbox rolls back
  defp clean_up(user, module, tenant, setting) do
    articles = Repo.all(from(a in Article, where: a.creator_id == ^user.id, select: a.id))
    schema = to_string(Article)

    Repo.query!(
      "DELETE FROM translation_groups WHERE id IN (SELECT group_id FROM translation_group_members WHERE entry_type = $1 AND entry_id = ANY($2))",
      [schema, articles]
    )

    Repo.query!("DELETE FROM content_identifiers WHERE schema = $1 AND entry_id = ANY($2)", [schema, articles])
    Repo.query!("DELETE FROM search_documents WHERE schema = $1 AND entry_id = ANY($2)", [schema, articles])
    Repo.delete_all(from(r in Receipt, where: r.actor_id == ^user.id))
    Repo.delete_all(from(r in Record, where: r.actor_id == ^user.id))

    Repo.delete_all(
      from(e in Brando.Activity.Event,
        where: e.user_id == ^user.id or e.approver_id == ^user.id or (e.schema == ^schema and e.entry_id in ^articles)
      )
    )

    Repo.delete_all(from(r in Brando.Revisions.Revision, where: r.creator_id == ^user.id))
    Repo.delete_all(from(a in Article, where: a.id in ^articles))
    # Their refs go with them, and the module's with the module
    Repo.delete_all(from(b in Brando.Content.Block, where: b.creator_id == ^user.id))
    Repo.delete_all(from(m in Brando.Content.Module, where: m.id == ^module.id))
    Repo.delete_all(from(i in Brando.Images.Image, where: i.creator_id == ^user.id))
    Repo.delete_all(from(e in Brando.Users.SecurityEvent, where: e.user_id == ^user.id))
    # Takes the connections and the two-factor row with it
    Repo.delete_all(from(u in Brando.Users.User, where: u.id == ^user.id))

    case setting do
      nil -> Repo.delete_all(from(s in Setting, where: is_nil(s.site_id) and is_nil(s.environment_id)))
      %Setting{enabled: enabled} -> switch!(tenant, enabled)
    end
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  defp grant!(c) do
    unboxed(fn ->
      Repo.insert!(%Grant{
        user_id: c.user.id,
        resource: MCP.resource(c.tenant),
        client_id: "https://client.example/meta.json",
        client_name: "Test Client",
        redirect_uri: "https://client.example/cb",
        scope: MCP.scope(),
        auto_apply: AutoApply.kind()
      })
    end)
  end

  defp propose!(c) do
    op = %{
      "op" => "create_translation",
      "source" => %{"content_type" => to_string(Article), "id" => c.source.id},
      "language" => "en",
      "ref" => "english"
    }

    {:ok, [op]} = Codec.decode_all([op])

    unboxed(fn ->
      {:ok, proposal} = Proposals.propose([op], c.user, origin: :mcp, client: "Test Client", replaces: :latest)
      proposal
    end)
  end

  # The automatic apply, in a task of its own that stops at `point`
  defp start_apply(c, proposal, grant, point) do
    :ok = :telemetry.attach(@handler, Repo.config()[:telemetry_prefix] ++ [:query], &__MODULE__.pause_at/4, nil)
    parent = self()

    task =
      Task.async(fn ->
        unboxed(fn ->
          Process.put(@handler, {parent, point})
          AutoApply.run(proposal.id, proposal.version, c.user, grant.id, c.tenant)
        end)
      end)

    assert_receive {:paused, ^point, pid}, 5_000
    {task, pid}
  end

  defp state(c, proposal) do
    unboxed(fn ->
      %{
        status: Repo.one!(from(r in Record, where: r.id == ^proposal.id, select: r.status)),
        receipt?: Repo.exists?(from(r in Receipt, where: r.id == ^proposal.id)),
        translated?: Brando.Translations.get_member(Article, c.source.id) != nil
      }
    end)
  end

  describe "the connection" do
    test "turned off, revoked or the endpoint switched off while an apply waits, nothing is written", c do
      changes = [
        fn grant -> :ok = MCP.set_auto_apply(grant.id, "none", c.user) end,
        fn grant -> :ok = MCP.revoke_grant(grant, c.user, "admin") end,
        fn _grant -> switch!(c.tenant, false) end
      ]

      for change <- changes do
        unboxed(fn -> switch!(c.tenant, true) end)
        grant = grant!(c)
        proposal = propose!(c)
        {task, pid} = start_apply(c, proposal, grant, :queued)

        # Committed before the apply reaches the connection
        unboxed(fn -> change.(grant) end)
        send(pid, {:resume, :queued})

        assert {:waiting, _reason} = Task.await(task, 10_000)
        assert %{status: "pending", receipt?: false, translated?: false} = state(c, proposal)
        :telemetry.detach(@handler)
      end
    end

    test "turned off after the apply locked it, the change waits for the apply, which is kept", c do
      grant = grant!(c)
      proposal = propose!(c)
      {task, pid} = start_apply(c, proposal, grant, :grant_locked)

      reset = Task.async(fn -> unboxed(fn -> MCP.set_auto_apply(grant.id, "none", c.user) end) end)
      await_lock_wait("mcp_grants")
      send(pid, {:resume, :grant_locked})

      assert {:applied, %Receipt{}} = Task.await(task, 10_000)
      assert :ok = Task.await(reset, 10_000)
      assert %{status: "applied", receipt?: true, translated?: true} = state(c, proposal)
      assert %Grant{auto_apply: "none"} = unboxed(fn -> Repo.get!(Grant, grant.id) end)
    end

    test "the endpoint switched off after the apply read it waits for the apply, which is kept", c do
      grant = grant!(c)
      proposal = propose!(c)
      # Past the connection's checks, about to write the receipt
      {task, pid} = start_apply(c, proposal, grant, :receipt)

      off = Task.async(fn -> unboxed(fn -> MCP.set_enabled(c.tenant, false, c.user) end) end)
      # On the switch's lock, which the apply holds shared
      await_lock_wait("pg_advisory_xact_lock(")
      # Not switched off before the apply commits
      assert unboxed(fn -> MCP.enabled?(c.tenant) end)
      send(pid, {:resume, :receipt})

      assert {:applied, %Receipt{}} = Task.await(task, 10_000)
      assert :ok = Task.await(off, 10_000)
      assert %{status: "applied", receipt?: true, translated?: true} = state(c, proposal)
      refute unboxed(fn -> MCP.enabled?(c.tenant) end)
      assert %Grant{revoked_reason: "endpoint_off"} = unboxed(fn -> Repo.get!(Grant, grant.id) end)
    end
  end

  describe "a Figma token refresh" do
    test "holding the settings row while Figma answers does not hold the apply up", c do
      grant = grant!(c)
      proposal = propose!(c)
      test = self()

      # The row lock a refresh keeps while it waits for Figma
      refresh =
        Task.async(fn ->
          unboxed(fn ->
            Repo.transaction(fn ->
              Repo.one!(from(s in MCP.setting_query(c.tenant), lock: "FOR UPDATE"))
              send(test, :locked)

              receive do
                :answer -> :ok
              after
                10_000 -> :ok
              end
            end)
          end)
        end)

      assert_receive :locked, 5_000

      apply =
        Task.async(fn -> unboxed(fn -> AutoApply.run(proposal.id, proposal.version, c.user, grant.id, c.tenant) end) end)

      assert {:ok, {:applied, %Receipt{}}} = Task.yield(apply, 5_000)
      send(refresh.pid, :answer)
      Task.await(refresh, 10_000)
      assert %{status: "applied", receipt?: true, translated?: true} = state(c, proposal)
    end
  end

  describe "discarding in the admin" do
    test "a discard committed first wins: nothing is applied", c do
      grant = grant!(c)
      proposal = propose!(c)
      {task, pid} = start_apply(c, proposal, grant, :queued)

      assert :ok = unboxed(fn -> Proposals.cancel(proposal.id, c.user) end)
      send(pid, {:resume, :queued})

      # The tool is told it was cancelled, not sent to review it
      assert {:settled, "cancelled", reason} = Task.await(task, 10_000)
      assert reason =~ "cancelled"
      assert %{status: "cancelled", receipt?: false, translated?: false} = state(c, proposal)
    end

    test "the person's apply committed first wins: the tool is told the person applied it", c do
      grant = grant!(c)
      proposal = propose!(c)
      # Checked the proposal pending, before it queues for the apply lock
      {task, pid} = start_apply(c, proposal, grant, :receipt_read)

      assert {:ok, _} = unboxed(fn -> Proposals.approve(proposal.id, proposal.version, c.user) end)
      assert {:ok, %Receipt{}} = unboxed(fn -> Proposals.apply(proposal.id, proposal.version, c.user) end)
      send(pid, {:resume, :receipt_read})

      assert {:settled, "applied", _reason} = Task.await(task, 10_000)
      assert %{status: "applied", receipt?: true, translated?: true} = state(c, proposal)
      assert %Record{auto_applied_grant_id: nil} = unboxed(fn -> Repo.get!(Record, proposal.id) end)
    end

    test "an apply holding the proposal wins: the discard that read it pending is refused", c do
      grant = grant!(c)
      proposal = propose!(c)
      {task, pid} = start_apply(c, proposal, grant, :grant_locked)

      discard = Task.async(fn -> unboxed(fn -> Proposals.cancel(proposal.id, c.user) end) end)
      await_lock_wait("content_proposals")
      send(pid, {:resume, :grant_locked})

      assert {:applied, %Receipt{}} = Task.await(task, 10_000)
      assert {:error, message} = Task.await(discard, 10_000)
      assert message =~ "already applied"
      assert %{status: "applied", receipt?: true, translated?: true} = state(c, proposal)
    end
  end

  # Telemetry handler, in the apply's process only: it stops once at its
  # point until the test lets it go on.
  @doc false
  def pause_at(_event, _measurements, metadata, _config) do
    with {test_pid, point} <- Process.get(@handler),
         ^point <- pause_point(metadata),
         false <- Process.get({@handler, point}, false) do
      Process.put({@handler, point}, true)
      send(test_pid, {:paused, point, self()})

      receive do
        {:resume, ^point} -> :ok
      after
        10_000 -> :ok
      end
    end

    :ok
  end

  # Queued behind the apply lock, before the proposal or the connection is
  # locked; and holding both
  defp pause_point(%{query: "SELECT pg_advisory_xact_lock" <> _}), do: :queued

  defp pause_point(%{source: "mcp_grants", query: "SELECT" <> _ = query}),
    do: if(query =~ "FOR UPDATE", do: :grant_locked)

  defp pause_point(%{source: "content_proposal_receipts", query: "INSERT" <> _}), do: :receipt
  defp pause_point(%{source: "content_proposal_receipts", query: "SELECT" <> _}), do: :receipt_read
  defp pause_point(_metadata), do: nil

  # Until another connection waits on a lock in a statement containing
  # `text`: a table's name, or the lock function's
  defp await_lock_wait(text, tries \\ 100) do
    waiting =
      unboxed(fn ->
        Repo.query!(
          """
          SELECT count(*) FROM pg_stat_activity
          WHERE datname = current_database() AND wait_event_type = 'Lock' AND query LIKE '%' || $1 || '%'
          """,
          [text]
        ).rows
      end)

    cond do
      waiting == [[1]] ->
        :ok

      tries == 0 ->
        flunk("nothing ever waited on the lock")

      true ->
        Process.sleep(20)
        await_lock_wait(text, tries - 1)
    end
  end
end
