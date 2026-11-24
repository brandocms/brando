defmodule Brando.Content.Proposals.SyncTranslationConcurrencyTest do
  # A sync_translation's or translate's apply against the translation sync
  # that recomputes the translation's pending version, on real connections
  # with commits between them: outside the sandbox, so the locks are real.
  # The apply stops after its recheck, before the save, until the test lets
  # it go on.
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Receipt
  alias Brando.Content.Proposals.Record
  alias Brando.Content.Proposals.SyncTranslation
  alias Brando.Content.Proposals.Translate
  alias Brando.SyncTest.Article
  alias Brando.Translations
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @handler __MODULE__

  setup do
    slug = "sync-race-#{System.unique_integer([:positive])}"

    {user, source, target} =
      unboxed(fn ->
        user = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil, config: %Brando.Users.UserConfig{})

        {:ok, source} =
          Brando.SyncTest.create_article(
            %{title: "Tittel", slug: slug, language: "no", status: "published", year: 2000},
            user
          )

        {:ok, target} = Translations.create_target(Article, source.id, :en, user)
        # The source's year, which the translation's pending version takes
        {:ok, _} = Brando.SyncTest.update_article(source.id, %{year: 2001}, user)
        {user, source, target}
      end)

    on_exit(fn ->
      :telemetry.detach(@handler)
      unboxed(fn -> clean_up(user) end)
    end)

    %{user: user, source: source, target: target}
  end

  # What the setup and the test wrote, which no sandbox rolls back
  defp clean_up(user) do
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
    Repo.delete_all(from(u in Brando.Users.User, where: u.id == ^user.id))
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  test "a pending version recomputed after the recheck is not what the apply saves", c do
    {:ok, proposal} =
      unboxed(fn -> Proposals.propose([%SyncTranslation{target: {Article, c.target.id}}], c.user) end)

    assert proposal.problems == []
    {:ok, _} = unboxed(fn -> Proposals.approve(proposal.id, proposal.version, c.user) end)

    # The source saved again, its sync not run yet
    unboxed(fn -> Repo.update_all(from(a in Article, where: a.id == ^c.source.id), set: [year: 2002]) end)

    {task, pid} = start_apply(c, proposal, :revision)
    %{group_id: group_id} = unboxed(fn -> Translations.get_member(Article, c.target.id) end)
    sync = Task.async(fn -> unboxed(fn -> Translations.sync_group(group_id) end) end)

    # The sync waits for the apply's lock on the group, or commits first
    early = Task.yield(sync, 500)
    send(pid, {:resume, :revision})

    assert {:ok, %Receipt{}} = Task.await(task, 10_000)
    assert {:ok, _} = if(early, do: elem(early, 1), else: Task.await(sync, 10_000))
    assert unboxed(fn -> Repo.get!(Article, c.target.id).year end) == 2001
  end

  # A translate batch: the translation's pending version is taken by its save
  # as the batch was checked against it, so a sync between the two waits
  for {name, sync} <- [
        {"the translation sync", :sync_group},
        {"an inline resync", :resync_target}
      ] do
    test "a translate batch saves the pending version it rechecked, with #{name} after the recheck", c do
      {:ok, proposal} = unboxed(fn -> Proposals.propose([translate_title(c.target)], c.user) end)
      assert proposal.problems == []
      {:ok, _} = unboxed(fn -> Proposals.approve(proposal.id, proposal.version, c.user) end)

      # The source saved again, its sync not run yet
      unboxed(fn -> Repo.update_all(from(a in Article, where: a.id == ^c.source.id), set: [year: 2002]) end)

      {task, pid} = start_apply(c, proposal, :revision)
      member = unboxed(fn -> Translations.get_member(Article, c.target.id) end)
      sync = Task.async(fn -> unboxed(fn -> run_sync(unquote(sync), member) end) end)

      # The sync waits for the apply's lock on the group, or commits first
      early = Task.yield(sync, 500)
      send(pid, {:resume, :revision})

      assert {:ok, %Receipt{}} = Task.await(task, 10_000)
      assert {:ok, _} = if(early, do: elem(early, 1), else: Task.await(sync, 10_000))

      assert %{title: "Title", year: 2001} = unboxed(fn -> Repo.get!(Article, c.target.id) end)
    end
  end

  # Another version made the group's source (`Translations.transfer_source/3`)
  # while the apply waits for the group: the test languages are two, so the
  # third version is enrolled under a language of its own by hand.
  test "a translate batch whose source changed while it waited for the group is refused as stale", c do
    {:ok, proposal} = unboxed(fn -> Proposals.propose([translate_title(c.target)], c.user) end)
    assert proposal.problems == []
    {:ok, _} = unboxed(fn -> Proposals.approve(proposal.id, proposal.version, c.user) end)

    third = unboxed(fn -> enrol_third_version(c) end)
    {transfer, pid} = start_paused(fn -> Translations.transfer_source(Article, third.id, c.user) end, :transfer)
    apply = Task.async(fn -> unboxed(fn -> Proposals.apply(proposal.id, proposal.version, c.user) end) end)

    # The apply waits for the transfer's lock on the group
    refute Task.yield(apply, 500)
    send(pid, {:resume, :transfer})

    assert {:ok, _} = Task.await(transfer, 10_000)
    assert {:error, message} = Task.await(apply, 10_000)
    assert message =~ "Prepare the proposal again"
    assert %{title: "Tittel"} = unboxed(fn -> Repo.get!(Article, c.target.id) end)
  end

  defp enrol_third_version(c) do
    {:ok, third} =
      Brando.SyncTest.create_article(
        %{title: "Tittel", slug: "#{c.source.slug}-3", language: "no", status: "published", year: 2000},
        c.user
      )

    %{group_id: group_id} = Translations.get_member(Article, c.source.id)

    Repo.insert!(%Translations.Member{
      group_id: group_id,
      entry_type: to_string(Article),
      entry_id: third.id,
      language: "sv",
      role: :target
    })

    third
  end

  defp run_sync(:sync_group, member), do: Translations.sync_group(member.group_id)
  defp run_sync(:resync_target, member), do: Translations.resync_target(member.group_id, member.id)

  defp translate_title(target) do
    {:ok, %{units: units}} = Translations.Work.translation_units(Article, target.id)
    units = Enum.filter(units, &(&1.answerable and &1.key == "title"))
    digest = Translations.Work.token(%{type: to_string(Article), id: target.id, language: "en"}, units)
    %Translate{target: {Article, target.id}, source_digest: digest, texts: %{"title" => "Title"}}
  end

  # The apply, in a task of its own that stops at `point`
  defp start_apply(c, proposal, point),
    do: start_paused(fn -> Proposals.apply(proposal.id, proposal.version, c.user) end, point)

  defp start_paused(fun, point) do
    :ok = :telemetry.attach(@handler, Repo.config()[:telemetry_prefix] ++ [:query], &__MODULE__.pause_at/4, nil)
    parent = self()

    task =
      Task.async(fn ->
        unboxed(fn ->
          Process.put(@handler, {parent, point})
          fun.()
        end)
      end)

    assert_receive {:paused, ^point, pid}, 5_000
    {task, pid}
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

  # The revision the translation is at, read after the recheck and before
  # the save
  defp pause_point(%{source: "revisions", query: "SELECT" <> _}), do: :revision
  # The transfer, holding the group's lock, before it moves the role
  defp pause_point(%{source: "translation_group_members", query: "UPDATE" <> _}), do: :transfer
  defp pause_point(_metadata), do: nil
end
