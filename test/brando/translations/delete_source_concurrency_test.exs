defmodule Brando.Translations.DeleteSourceConcurrencyTest do
  # A translation created while its source is deleted with its translations
  # (#3926), on real connections with commits between them: outside the
  # sandbox, so the locks are real. The enrolment holds its transaction open
  # until the test lets it commit; the delete waits for it, then finds the
  # group changed and deletes nothing.
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.SyncTest.Article
  alias Brando.Translations
  alias Brando.Translations.Member
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    slug = "delete-race-#{System.unique_integer([:positive])}"

    {user, source} =
      unboxed(fn ->
        user = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil, config: %Brando.Users.UserConfig{})

        {:ok, source} =
          Brando.SyncTest.create_article(%{title: "Tittel", slug: slug, language: "no", status: "published"}, user)

        # A translation the test app has no language for: an English article
        # in the group as German, which leaves English to create
        {:ok, german} =
          Brando.SyncTest.create_article(%{title: "Titel", slug: slug, language: "en", status: "draft"}, user)

        {:ok, _} = Translations.enroll_source(Article, source.id, user)
        %{group_id: group_id} = Translations.get_member(Article, source.id)

        Repo.insert!(%Member{
          group_id: group_id,
          entry_type: to_string(Article),
          entry_id: german.id,
          language: "de",
          role: :target,
          synchronized: true
        })

        {user, source}
      end)

    on_exit(fn -> unboxed(fn -> clean_up(user) end) end)
    %{user: user, source: source}
  end

  defp clean_up(user) do
    articles = Repo.all(from(a in Article, where: a.creator_id == ^user.id, select: a.id))
    schema = to_string(Article)

    Repo.query!(
      "DELETE FROM translation_groups WHERE id IN (SELECT group_id FROM translation_group_members WHERE entry_type = $1 AND entry_id = ANY($2))",
      [schema, articles]
    )

    Repo.query!("DELETE FROM content_identifiers WHERE schema = $1 AND entry_id = ANY($2)", [schema, articles])
    Repo.query!("DELETE FROM search_documents WHERE schema = $1 AND entry_id = ANY($2)", [schema, articles])

    Repo.delete_all(
      from(e in Brando.Activity.Event, where: e.user_id == ^user.id or (e.schema == ^schema and e.entry_id in ^articles))
    )

    Repo.delete_all(from(r in Brando.Revisions.Revision, where: r.creator_id == ^user.id))
    Repo.delete_all(from(a in Article, where: a.id in ^articles))
    Repo.delete_all(from(u in Brando.Users.User, where: u.id == ^user.id))
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  test "a delete waits for a translation being created, and then deletes nothing", c do
    shown = unboxed(fn -> Translations.source_group(Article, c.source.id).fingerprint end)
    test = self()

    enrolment =
      Task.async(fn ->
        unboxed(fn ->
          Brando.Repo.transaction(fn ->
            {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
            send(test, :enrolled)

            receive do
              :commit -> target
            end
          end)
        end)
      end)

    assert_receive :enrolled, 10_000

    delete =
      Task.async(fn -> unboxed(fn -> Translations.delete_with_translations(Article, c.source.id, shown, c.user) end) end)

    # The delete waits for the enrolment's lock on the source
    assert Task.yield(delete, 500) == nil
    send(enrolment.pid, :commit)

    assert {:ok, %Article{id: target_id}} = Task.await(enrolment, 10_000)
    assert {:error, :group_changed} = Task.await(delete, 10_000)

    unboxed(fn ->
      assert Repo.get(Article, c.source.id)
      assert %{role: :target} = Translations.get_member(Article, target_id)
    end)
  end
end
