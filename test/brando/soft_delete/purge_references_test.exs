defmodule Brando.Persons do
  # The context of the test schemas `Brando.MigrationTest.Profile` and
  # `Brando.Persons.Person`: a purge hook a test sets for its own process
  def before_purge(schema, ids) do
    if hook = Process.get({__MODULE__, :before_purge}), do: hook.(schema, ids)
    :ok
  end
end

defmodule Brando.SoftDelete.PurgeReferencesTest do
  # The trash purge, for an expired row that rows not expired still refer to
  use Brando.ConnCase, async: true

  import ExUnit.CaptureLog

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page
  alias Brando.SoftDelete.Query
  alias Brando.Users.User

  setup do
    put_test_env(:tenancy_mode, :none)
    %{user: Factory.insert(:random_user, role: :superuser)}
  end

  defp page!(user, attrs) do
    params = Map.merge(%{language: "en", template: "default.html", status: :published}, attrs)
    {:ok, page} = Pages.create_page(params, user)
    page
  end

  defp expire(schema, ids) do
    old = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -31 * 86_400)
    Repo.update_all(from(t in schema, where: t.id in ^ids), set: [deleted_at: old])
  end

  defp trail(page), do: Enum.map(Repo.get!(Page, page.id).breadcrumbs, & &1["title"])

  test "an expired page's remaining children and fragments lose the reference, and the rest is purged", %{user: user} do
    home = page!(user, %{title: "Home", uri: "home"})
    about = page!(user, %{title: "About", uri: "home/about", parent_id: home.id})
    team = page!(user, %{title: "Team", uri: "home/about/team", parent_id: about.id})
    jobs = page!(user, %{title: "Jobs", uri: "home/about/jobs", parent_id: about.id})
    fragment = Factory.insert(:fragment, creator: user, page_id: about.id, parent_key: "about", key: "intro")
    stale_user = Factory.insert(:random_user)
    app_name = Brando.config(:app_name)

    {:ok, _} = Pages.delete_page(jobs.id, user)
    {:ok, _} = Pages.delete_page(about.id, user)
    expire(Page, [about.id])
    expire(User, [stale_user.id])
    assert trail(team) == [app_name, "Home", "Team"]

    refute Enum.any?(Query.clean_up_soft_deletions(), &match?({:error, _}, &1))

    refute Repo.get(Page, about.id)
    refute Repo.get(User, stale_user.id)
    assert %{parent_id: nil, deleted_at: nil} = Repo.get!(Page, team.id)
    # Trashed after its parent, not expired: kept, at the top
    assert %{parent_id: nil, deleted_at: %DateTime{}} = Repo.get!(Page, jobs.id)
    assert %{page_id: nil} = Repo.get!(Fragment, fragment.id)
    # The child is at the top now: its trail leaves the old grandparent out
    assert trail(team) == [app_name, "Team"]
  end

  test "a revision taken before the purge restores, keeping the reference the purge cleared", %{user: user} do
    about = page!(user, %{title: "About", uri: "about"})
    team = page!(user, %{title: "Team", uri: "about/team", parent_id: about.id})
    fragment = Factory.insert(:fragment, creator: user, page_id: about.id, parent_key: "about", key: "intro")
    {:ok, team_revision} = Brando.Revisions.create_revision(Repo.get!(Page, team.id), user)
    {:ok, fragment_revision} = Brando.Revisions.create_revision(Repo.get!(Fragment, fragment.id), user)

    {:ok, _} = Pages.delete_page(about.id, user)
    expire(Page, [about.id])
    refute Enum.any?(Query.clean_up_soft_deletions(), &match?({:error, _}, &1))

    assert {:ok, %{parent_id: nil}} = Brando.Revisions.set_entry_to_revision(Page, team.id, team_revision.revision, user)

    assert {:ok, %{page_id: nil}} =
             Brando.Revisions.set_entry_to_revision(Fragment, fragment.id, fragment_revision.revision, user)
  end

  defp insert_profile!(deleted_at) do
    id = Ecto.UUID.generate()

    Repo.query!(
      "INSERT INTO persons_profile (id, deleted_at, inserted_at, updated_at) VALUES ($1, $2, now(), now())",
      [Ecto.UUID.dump!(id), deleted_at]
    )

    id
  end

  defp profile_ids, do: Repo.all(from(p in "persons_profile", select: type(p.id, Ecto.UUID)))

  test "the rows the hook is given are the rows deleted, though one is restored after they are read" do
    old = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -31 * 86_400)
    first = insert_profile!(old)
    second = insert_profile!(old)
    test = self()

    Process.put({Brando.Persons, :before_purge}, fn
      Brando.MigrationTest.Profile, ids ->
        send(test, {:hook, Enum.sort(ids)})
        # Restored after the purge read the ids: the purge holds the rows
        Repo.update_all(from(p in "persons_profile", where: p.id == type(^second, Ecto.UUID)),
          set: [deleted_at: nil]
        )

      _schema, _ids ->
        :ok
    end)

    Query.clean_up_soft_deletions()

    assert_received {:hook, ids}
    assert ids == Enum.sort([first, second])
    assert Enum.filter(profile_ids(), &(&1 in ids)) == []
  end

  test "a schema whose purge fails is logged, and the schemas after it are still purged", %{user: user} do
    # A live person still refers to an expired profile: `persons_profile` is
    # purged before `pages` and `users`, and its delete raises
    profile_id = Ecto.UUID.generate()
    old = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -31 * 86_400)

    Repo.query!(
      "INSERT INTO persons_profile (id, deleted_at, inserted_at, updated_at) VALUES ($1, $2, now(), now())",
      [Ecto.UUID.dump!(profile_id), old]
    )

    Repo.query!(
      "INSERT INTO persons (id, email, profile_id, inserted_at, updated_at) VALUES ($1, 'a@example.com', $2, now(), now())",
      [Ecto.UUID.dump!(Ecto.UUID.generate()), Ecto.UUID.dump!(profile_id)]
    )

    stale_page = page!(user, %{title: "Old", uri: "old"})
    stale_user = Factory.insert(:random_user)
    expire(Page, [stale_page.id])
    expire(User, [stale_user.id])

    log =
      capture_log(fn ->
        assert {:error, Brando.MigrationTest.Profile} in Query.clean_up_soft_deletions()
      end)

    assert log =~ "Purging Brando.MigrationTest.Profile failed: foreign_key_violation persons persons_profile_id_fkey"
    refute Repo.get(Page, stale_page.id)
    refute Repo.get(User, stale_user.id)

    # The job tries every schema, then fails, so the failure shows
    assert capture_log(fn ->
             assert {:error, _} = Brando.Worker.SoftDeletePurger.perform(%Oban.Job{args: %{}})
           end) =~ "Purging Brando.MigrationTest.Profile failed"
  end
end
