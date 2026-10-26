defmodule Brando.Migrations.HashPreviewKeysTest do
  use Brando.ConnCase

  alias Brando.Sites.Preview
  alias BrandoIntegration.Repo

  @migration Application.app_dir(:brando, "priv/templates/brando.upgrade/migrations/brando_222_hash_preview_keys.exs")

  setup_all do
    [{module, _bytecode}] = Code.compile_file(@migration)

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

    %{migration: module}
  end

  test "hashes the keys stored before, once, and their links keep working", %{migration: migration} do
    user = Brando.Factory.insert(:random_user, avatar: nil)

    insert = fn key ->
      Repo.insert!(%Preview{
        creator_id: user.id,
        preview_key: key,
        html: Brando.Utils.term_to_binary("<main>Shared draft</main>"),
        expires_at: DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.truncate(:second)
      })
    end

    old = insert.("Zx81kQ0pLm-_")
    new = insert.(Preview.hash_key("fresh-key"))

    # Run twice: hashed keys are left as they are
    for _run <- 1..2 do
      Ecto.Migrator.up(Repo, System.unique_integer([:positive]), migration, log: false, migration_lock: false)

      assert Repo.get!(Preview, old.id).preview_key == Preview.hash_key("Zx81kQ0pLm-_")
      assert Repo.get!(Preview, new.id).preview_key == Preview.hash_key("fresh-key")
    end

    Brando.Cache.Query.evict(old)
    assert %{status: 200} = BrandoWeb.PreviewController.show(build_conn(), %{"preview_key" => "Zx81kQ0pLm-_"})
  end
end
