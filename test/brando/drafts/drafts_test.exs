defmodule Brando.DraftsTest do
  use Brando.ConnCase, async: false
  alias Brando.Drafts
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
end
