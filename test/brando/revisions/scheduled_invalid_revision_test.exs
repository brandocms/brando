defmodule Brando.Revisions.ScheduledInvalidRevisionTest do
  # A scheduled revision whose nested record no longer validates (a var that
  # lost its required label) has no errors at the top level: it is cancelled
  # at once all the same, and Activity names the field that holds the record.
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.InvalidRevisions
  alias Brando.Pages.Page
  alias Brando.Revisions
  alias Brando.Worker.EntryPublisher

  setup do
    {:ok, %{user: Factory.insert(:random_user)}}
  end

  test "is cancelled, and Activity names the nested field", %{user: user} do
    {page, revision} = InvalidRevisions.page_with_invalid_var!(user)
    {1, _} = Revisions.mark_revision_scheduled(Page, page.id, revision, true)

    assert {:cancel, :invalid} = EntryPublisher.perform(InvalidRevisions.scheduled_job(page, revision, user))

    assert Repo.get!(Page, page.id).title == "Changed since"
    assert {:ok, revisions} = Revisions.list_revision_metadata(Page, page.id)
    refute Enum.find(revisions, &(&1.revision == revision)).scheduled

    assert [%{fields: ["vars"], details: %{"scheduled_revision" => %{"reason" => "invalid"}}}] =
             Page |> Brando.Activity.for_entry(page.id) |> Enum.filter(&(&1.details["scheduled_revision"] != nil))
  end

  # Two restores taking the same unique value at once: the index refuses the
  # later one, and trying again may well go through. Anything else is final.
  test "a refusal is retried only for a unique-index conflict, at any depth" do
    changeset = Ecto.Changeset.change(%Page{vars: []})
    unique = [constraint: :unique, constraint_name: "pages_uri_index"]

    assert EntryPublisher.unique_conflict?(Ecto.Changeset.add_error(changeset, :uri, "has already been taken", unique))

    var =
      %Brando.Content.Var{} |> Ecto.Changeset.change() |> Ecto.Changeset.add_error(:key, "has already been taken", unique)

    assert EntryPublisher.unique_conflict?(Ecto.Changeset.put_assoc(changeset, :vars, [var]))

    refute EntryPublisher.unique_conflict?(
             Ecto.Changeset.add_error(changeset, :title, "can't be blank", validation: :required)
           )

    refute EntryPublisher.unique_conflict?(
             Ecto.Changeset.add_error(changeset, :uri, "has already been taken",
               validation: :unsafe_unique,
               fields: [:uri]
             )
           )
  end

  # A value another entry holds for good fails the same way on every
  # attempt: it is retried only a few times, then dropped like any other
  # refusal. A job built without attempts counts as its first.
  test "a unique conflict is retried on the first attempts only" do
    taken =
      %Page{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.add_error(:uri, "has already been taken",
        constraint: :unique,
        constraint_name: "pages_uri_index"
      )

    blank = Ecto.Changeset.add_error(Ecto.Changeset.change(%Page{}), :title, "can't be blank", validation: :required)
    job = fn attempt -> %Oban.Job{attempt: attempt, max_attempts: 10} end

    assert EntryPublisher.retry_refused_revision?(job.(1), taken)
    assert EntryPublisher.retry_refused_revision?(job.(2), taken)
    refute EntryPublisher.retry_refused_revision?(job.(3), taken)
    refute EntryPublisher.retry_refused_revision?(job.(10), taken)
    assert EntryPublisher.retry_refused_revision?(%Oban.Job{}, taken)
    assert EntryPublisher.retry_refused_revision?(job.(0), taken)
    refute EntryPublisher.retry_refused_revision?(%Oban.Job{attempt: 1, max_attempts: 1}, taken)

    refute EntryPublisher.retry_refused_revision?(job.(1), blank)
  end
end
