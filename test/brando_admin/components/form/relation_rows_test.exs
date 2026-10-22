defmodule BrandoAdmin.Components.Form.RelationRowsTest do
  # A form keeping the relation its editor changed over another editor's
  # save (`Form.take_saved_entry/1`).
  use ExUnit.Case, async: true

  alias Brando.Repo
  alias BrandoAdmin.Components.Form.RelationRows

  defmodule Tag do
    @moduledoc false
    use Ecto.Schema

    schema "tags" do
    end
  end

  defmodule Photo do
    @moduledoc false
    use Ecto.Schema

    schema "photos" do
      many_to_many :tags, Tag, join_through: "photos_to_tags", on_replace: :delete
    end

    def changeset(photo, params),
      do: Brando.M2M.cast_collection(Ecto.Changeset.cast(photo, params, []), :tags, Brando.Repo.repo(), Tag, false)
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo.repo())
    [kept, added, saved] = for _ <- 1..3, do: Repo.insert!(%Tag{})
    photo = Repo.insert!(%Photo{tags: [kept]}) |> Repo.preload(:tags, force: true)
    %{photo: photo, kept: kept, added: added, saved: saved}
  end

  # B added a tag the entry didn't have (cast as an `:update` of the loaded
  # tag); A's save added another.
  test "a many_to_many keeps the entries this form added", c do
    previous = Photo.changeset(c.photo, %{"tags" => [c.kept.id, c.added.id]})
    saved = c.photo |> Ecto.Changeset.change() |> Ecto.Changeset.put_assoc(:tags, [c.kept, c.saved]) |> Repo.update!()
    saved = Ecto.Changeset.change(Repo.preload(saved, :tags, force: true))

    carried = RelationRows.carry(saved, previous, :tags)

    assert carried |> RelationRows.rows(:tags) |> Enum.sort() == Enum.sort([[id: c.kept.id], [id: c.added.id]])
  end
end
