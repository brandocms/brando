defmodule Brando.SoftDelete.PurgeEntriesTest do
  # Deleting entries in the trash for good now, in the caller's transaction,
  # the way the scheduled purge deletes an expired row
  use Brando.ConnCase, async: true

  alias Brando.Factory
  alias Brando.Images.Image
  alias Brando.Pages
  alias Brando.SoftDelete.Query
  alias Brando.Users.User

  setup do
    put_test_env(:tenancy_mode, :none)
    %{user: Factory.insert(:random_user, role: :superuser)}
  end

  defp trash(schema, id),
    do: Repo.update_all(from(t in schema, where: t.id == ^id), set: [deleted_at: DateTime.utc_now(:second)])

  test "a type whose context has no before_purge: the entry in the trash goes, not yet expired", %{user: user} do
    image = Factory.insert(:image, creator: user)
    trash(Image, image.id)

    assert {:ok, :ok} = Repo.transaction(fn -> Query.purge_entries(Image, [image.id], user) end)

    refute Repo.get(Image, image.id)
  end

  test "an entry not in the trash is left", %{user: user} do
    image = Factory.insert(:image, creator: user)

    assert {:ok, :ok} = Repo.transaction(fn -> Query.purge_entries(Image, [image.id], user) end)

    assert Repo.get(Image, image.id)
  end

  test "an entry something still refers to is kept, and the transaction goes on", %{user: user} do
    creator = Factory.insert(:random_user)

    {:ok, page} =
      Pages.create_page(
        %{language: "en", template: "default.html", title: "Live", uri: "live", status: :published},
        creator
      )

    trash(User, creator.id)

    assert {:ok, {{:error, {:referenced, "pages_creator_id_fkey"}}, %Pages.Page{}}} =
             Repo.transaction(fn ->
               result = Query.purge_entries(User, [creator.id], user)
               # The transaction is still usable
               {result, Repo.get!(Pages.Page, page.id)}
             end)

    assert Repo.get(User, creator.id)
  end
end
