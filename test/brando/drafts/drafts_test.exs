defmodule Brando.DraftsTest do
  use Brando.ConnCase, async: false
  alias Brando.DraftFixtures
  alias Brando.Drafts
  alias Brando.Drafts.Content
  alias Brando.Drafts.EntryDraft

  setup do
    user = Brando.Factory.insert(:random_user)
    identity = Drafts.identity(Brando.Pages.Page, nil, user.id)

    {:ok,
     identity: identity, id: Ecto.UUID.generate(), payload: %{"main" => %{"title" => "Working title"}, "blocks" => %{}}}
  end

  test "coalesces writes and rejects out-of-order captures", ctx do
    assert {:ok, first} = Drafts.write(ctx.identity, ctx.id, 2, ctx.payload, "base", 0)
    assert {:ok, _} = Drafts.write(ctx.identity, ctx.id, 1, %{}, "base", 0)
    assert Drafts.get(ctx.identity, ctx.id).payload == ctx.payload

    assert {:ok, latest} =
             Drafts.write(ctx.identity, ctx.id, 3, put_in(ctx.payload, ["main", "title"], "Latest"), "base", 0)

    assert first.id == latest.id
    assert latest.generation == 3
    assert length(Drafts.list(ctx.identity)) == 1
  end

  test "isolates copies by user, entry, form and environment", ctx do
    assert {:ok, _} = Drafts.write(ctx.identity, ctx.id, 1, ctx.payload, "base", 0)

    for changed <- [
          %{owner_id: -1},
          %{entry_id: 1},
          %{entry_type: "Other.Schema"},
          %{form_name: "other"},
          %{scope: "tenant_elsewhere_live"}
        ] do
      identity = Map.merge(ctx.identity, changed)
      assert Drafts.get(identity, ctx.id) == nil
      assert Drafts.list(identity) == []
      assert {:error, :not_found} = Drafts.write(identity, ctx.id, 2, %{}, "base", 0)
      assert {:error, :not_found} = Drafts.resolve(identity, ctx.id, 2)
    end
  end

  test "save resolves only its captured generation and late writes cannot resurrect it", ctx do
    assert {:ok, _} = Drafts.write(ctx.identity, ctx.id, 3, ctx.payload, "base", 0)
    assert {:ok, _} = Drafts.resolve(ctx.identity, ctx.id, 2)
    assert [%{resolved_at: nil}] = Drafts.list(ctx.identity)
    assert {:ok, _} = Drafts.resolve(ctx.identity, ctx.id, 3)
    assert Drafts.list(ctx.identity) == []
    assert {:error, :closed} = Drafts.write(ctx.identity, ctx.id, 4, ctx.payload, "base", 0)
    assert Drafts.get(ctx.identity, ctx.id).payload == ctx.payload
  end

  test "save before the first capture also rejects a late write", ctx do
    assert {:ok, _} = Drafts.resolve(ctx.identity, ctx.id, 1)
    assert {:error, :closed} = Drafts.write(ctx.identity, ctx.id, 1, ctx.payload, "base", 0)
    assert Drafts.list(ctx.identity) == []
  end

  test "successful save releases its payload but keeps a marker blocking late captures", ctx do
    assert {:ok, _} = Drafts.write(ctx.identity, ctx.id, 3, ctx.payload, "base", 0)
    assert {:ok, _} = Drafts.resolve(ctx.identity, ctx.id, 2, compact: true)
    assert Drafts.get(ctx.identity, ctx.id).payload == ctx.payload
    assert {:ok, marker} = Drafts.resolve(ctx.identity, ctx.id, 3, compact: true)
    assert marker.payload == %{}
    assert marker.checksum == Drafts.checksum(%{})
    assert marker.generation == 3
    assert marker.resolved_at
    assert {:error, :closed} = Drafts.write(ctx.identity, ctx.id, 4, ctx.payload, "base", 0)
    assert Drafts.list(ctx.identity) == []
  end

  test "saving a restored copy compacts its equivalents and preserves divergent or newer work", ctx do
    {:ok, selected} = Drafts.write(ctx.identity, ctx.id, 1, ctx.payload, "base", 0)
    {:ok, duplicate} = Drafts.write(ctx.identity, Ecto.UUID.generate(), 1, ctx.payload, "base", 0)
    edited = put_in(ctx.payload, ["main", "title"], "Newer work")
    {:ok, newer} = Drafts.write(ctx.identity, selected.id, 2, edited, "base", 0)
    {:ok, independent} = Drafts.write(ctx.identity, Ecto.UUID.generate(), 1, edited, "base", 0)
    {:ok, failed} = Drafts.begin_restore(ctx.identity, independent.id)

    assert {:ok, _} = Drafts.resolve_equivalent(ctx.identity, selected, compact: true)
    assert Drafts.get(ctx.identity, duplicate.id).payload == %{}
    assert Drafts.get(ctx.identity, newer.id).payload == edited
    assert Drafts.get(ctx.identity, failed.id).payload == edited
    assert length(Drafts.list(ctx.identity)) == 2

    assert {:ok, _} = Drafts.resolve_equivalent(ctx.identity, newer, compact: true)
    assert Drafts.get(ctx.identity, newer.id).payload == %{}
  end

  test "save compacts baseline matches with initialization noise without touching other content", ctx do
    baseline = DraftFixtures.payload()
    {:ok, matching} = Drafts.write(ctx.identity, ctx.id, 1, DraftFixtures.initialized(baseline), "base", 0)
    {:ok, other} = Drafts.write(ctx.identity, Ecto.UUID.generate(), 1, ctx.payload, "base", 0)
    assert {:ok, 1} = Drafts.resolve_unchanged(ctx.identity, Content.checksum(baseline), 0, compact: true)
    assert Drafts.get(ctx.identity, matching.id).payload == %{}
    assert Drafts.get(ctx.identity, matching.id).checksum == Drafts.checksum(%{})
    assert Drafts.get(ctx.identity, other.id).payload == ctx.payload
  end

  test "independent editing sessions keep their own copies", ctx do
    other_id = Ecto.UUID.generate()
    assert {:ok, _} = Drafts.write(ctx.identity, ctx.id, 1, ctx.payload, "base", 0)
    assert {:ok, _} = Drafts.write(ctx.identity, other_id, 1, %{"main" => %{"title" => "Another tab"}}, "base", 0)
    assert {:ok, _} = Drafts.resolve(ctx.identity, ctx.id, 1)
    assert [%{id: ^other_id}] = Drafts.list(ctx.identity)
  end

  test "restore attempts and dismissal survive reload and freeze the original", ctx do
    assert {:ok, _} = Drafts.write(ctx.identity, ctx.id, 1, ctx.payload, "base", 0)
    assert {:ok, _} = Drafts.begin_restore(ctx.identity, ctx.id)
    assert [copy] = Drafts.list(ctx.identity)
    assert copy.dismissed_at
    assert copy.attempted_at
    assert copy.payload == ctx.payload
    assert {:error, :closed} = Drafts.write(ctx.identity, ctx.id, 2, %{}, "base", 0)
    assert {:ok, _} = Drafts.begin_restore(ctx.identity, ctx.id)
    assert {:ok, _} = Drafts.discard(ctx.identity, ctx.id)
    assert Drafts.list(ctx.identity) == []
  end

  test "purges expired copies while retaining recent resolved copies", ctx do
    assert {:ok, _} = Drafts.write(ctx.identity, ctx.id, 1, ctx.payload, "base", 0)
    Drafts.resolve(ctx.identity, ctx.id, 1)
    assert {0, _} = Drafts.purge()
    Brando.Repo.update_all(EntryDraft, set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)])
    assert {1, _} = Drafts.purge()
  end

  test "legacy copies matching saved content stay resolved when the saved baseline changes", ctx do
    saved = DraftFixtures.payload()
    captured = DraftFixtures.initialized(saved)
    {:ok, copy} = Drafts.write(ctx.identity, ctx.id, 1, captured, "base", 0)

    assert Drafts.candidates(ctx.identity, baseline: Content.checksum(saved), schema_version: 0) == []
    assert [^copy] = Drafts.list(ctx.identity)
    assert {:ok, 1} = Drafts.resolve_unchanged(ctx.identity, Content.checksum(saved), 0)
    assert {:ok, 0} = Drafts.resolve_unchanged(ctx.identity, Content.checksum(saved), 0)
    updated = put_in(saved, ["main", "title"], "New saved content")
    assert Drafts.candidates(ctx.identity, baseline: Content.checksum(updated), schema_version: 0) == []
    assert Drafts.list(ctx.identity) == []
    retained = Drafts.get(ctx.identity, copy.id)
    assert retained.resolved_at
    assert retained.discarded_at == nil
    assert retained.payload == captured
    assert retained.checksum == copy.checksum
    assert retained.generation == copy.generation
    assert retained.updated_at == copy.updated_at
  end

  test "baseline reconciliation preserves real unsaved changes regardless of age", ctx do
    saved = DraftFixtures.payload()
    {:ok, matching} = Drafts.write(ctx.identity, ctx.id, 1, DraftFixtures.initialized(saved), "base", 0)
    edited = put_in(saved, ["main", "title"], "Older but genuinely unsaved work")
    {:ok, other} = Drafts.write(ctx.identity, Ecto.UUID.generate(), 1, edited, "base", 0)
    other |> Ecto.Changeset.change(updated_at: DateTime.add(DateTime.utc_now(), -86_400)) |> Brando.Repo.update!()

    assert {:ok, 1} = Drafts.resolve_unchanged(ctx.identity, Content.checksum(saved), 0)
    assert [remaining] = Drafts.list(ctx.identity)
    assert remaining.id == other.id
    assert remaining.payload == edited
    assert Drafts.get(ctx.identity, matching.id).resolved_at
  end

  test "baseline reconciliation preserves a copy that another tab has changed", ctx do
    {:ok, _} = Drafts.write(ctx.identity, ctx.id, 1, ctx.payload, "base", 0)
    edited = put_in(ctx.payload, ["main", "title"], "Newer input in another tab")
    {:ok, newer} = Drafts.write(ctx.identity, ctx.id, 2, edited, "base", 0)
    assert {:ok, 0} = Drafts.resolve_unchanged(ctx.identity, Content.checksum(ctx.payload), 0)
    assert [^newer] = Drafts.list(ctx.identity)
  end

  test "equal content is one choice, while restore contracts and saved baselines remain distinct", ctx do
    saved = DraftFixtures.payload()
    initialized = DraftFixtures.initialized(saved)
    {:ok, _} = Drafts.write(ctx.identity, ctx.id, 1, saved, "base", 0)
    {:ok, duplicate} = Drafts.write(ctx.identity, Ecto.UUID.generate(), 1, initialized, "base", 0)
    assert [^duplicate] = Drafts.candidates(ctx.identity)
    assert length(Drafts.list(ctx.identity)) == 2

    {:ok, _} = Drafts.write(ctx.identity, Ecto.UUID.generate(), 1, saved, "changed-entry", 0)
    {:ok, _} = Drafts.write(ctx.identity, Ecto.UUID.generate(), 1, saved, "base", 1)
    {:ok, unsupported} = Drafts.write(ctx.identity, Ecto.UUID.generate(), 1, saved, "base", 0)
    unsupported |> Ecto.Changeset.change(format_version: 999) |> Brando.Repo.update!()
    assert length(Drafts.candidates(ctx.identity)) == 4

    candidates = Drafts.candidates(ctx.identity, baseline: Content.checksum(saved), schema_version: 0)
    assert length(candidates) == 2
    assert Enum.any?(candidates, &(&1.format_version == 999))
    assert Enum.any?(candidates, &(&1.schema_version == 1))
    assert {:ok, 3} = Drafts.resolve_unchanged(ctx.identity, Content.checksum(saved), 0)
    assert MapSet.new(Drafts.list(ctx.identity)) == MapSet.new(candidates)
  end

  test "dismissing and discarding a duplicate choice affects its equivalents without deleting content", ctx do
    {:ok, _} = Drafts.write(ctx.identity, ctx.id, 1, ctx.payload, "base", 0)
    {:ok, copy} = Drafts.write(ctx.identity, Ecto.UUID.generate(), 1, ctx.payload, "base", 0)
    assert {:ok, _} = Drafts.dismiss(ctx.identity, copy.id)
    assert Enum.all?(Drafts.list(ctx.identity), & &1.dismissed_at)
    assert {:ok, _} = Drafts.discard(ctx.identity, copy.id)
    assert Drafts.candidates(ctx.identity) == []
    assert Drafts.get(ctx.identity, ctx.id).payload == ctx.payload
    assert Drafts.get(ctx.identity, copy.id).payload == ctx.payload
  end

  test "discarding one choice preserves another session that has since diverged", ctx do
    {:ok, _} = Drafts.write(ctx.identity, ctx.id, 1, ctx.payload, "base", 0)
    {:ok, other} = Drafts.write(ctx.identity, Ecto.UUID.generate(), 1, ctx.payload, "base", 0)
    edited = put_in(ctx.payload, ["main", "title"], "Other tab's newer edit")
    {:ok, newer} = Drafts.write(ctx.identity, other.id, 2, edited, "base", 0)
    assert {:ok, _} = Drafts.discard(ctx.identity, ctx.id)
    assert [^newer] = Drafts.candidates(ctx.identity)
  end

  test "saving a restored choice resolves equivalents but never a newer selected generation", ctx do
    {:ok, selected} = Drafts.write(ctx.identity, ctx.id, 1, ctx.payload, "base", 0)
    {:ok, duplicate} = Drafts.write(ctx.identity, Ecto.UUID.generate(), 1, ctx.payload, "base", 0)
    edited = put_in(ctx.payload, ["main", "title"], "Typed during save")
    {:ok, newer} = Drafts.write(ctx.identity, selected.id, 2, edited, "base", 0)

    assert {:ok, _} = Drafts.resolve_equivalent(ctx.identity, selected)
    assert [^newer] = Drafts.list(ctx.identity)
    assert Drafts.get(ctx.identity, duplicate.id).resolved_at
    assert Drafts.get(ctx.identity, duplicate.id).payload == ctx.payload
  end
end
