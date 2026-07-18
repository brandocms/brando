defmodule Brando.M2MTest do
  use ExUnit.Case, async: true
  doctest Brando.M2M

  alias Ecto.Changeset

  defmodule Tag do
    use Ecto.Schema

    schema "tags" do
    end
  end

  defmodule Photo do
    use Ecto.Schema
    import Ecto.Changeset, only: [cast: 3]
    import Ecto.Query

    schema "photos" do
      many_to_many :tags, Tag,
        join_through: "photos_to_tags",
        on_delete: :delete_all,
        on_replace: :delete
    end

    def changeset(struct, params \\ %{}) do
      struct
      |> cast(params, ~w())
      |> Brando.M2M.cast_collection(:tags, Brando.Repo.repo(), Tag, false)
    end

    def custom_function_changeset(struct, params \\ %{}) do
      struct
      |> cast(params, ~w())
      |> Brando.M2M.cast_collection(
        :tags,
        fn ids ->
          # Convert Strings back to Integers for demonstration
          ids = Enum.map(ids, &String.to_integer/1)

          Brando.Repo.all(from t in Tag, where: t.id in ^ids)
        end,
        false
      )
    end
  end

  setup do
    # Explicitly get a connection before each test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Brando.Repo.repo())

    tag_1 = Brando.Repo.insert!(%Tag{})
    tag_2 = Brando.Repo.insert!(%Tag{})

    {:ok, [tag_1: tag_1, tag_2: tag_2]}
  end

  test "association for new model", %{tag_1: tag_1} do
    changeset = Photo.changeset(%Photo{}, %{tags: [tag_1.id]})

    photo = Brando.Repo.insert!(changeset)
    photo = Brando.Repo.get(Photo, photo.id) |> Brando.Repo.preload(:tags)

    assert photo.tags == [tag_1]
  end

  test "association for existing model", %{tag_1: tag_1, tag_2: tag_2} do
    changeset = Photo.changeset(%Photo{}, %{tags: [tag_1.id]})
    photo = Brando.Repo.insert!(changeset)

    changeset = Photo.changeset(photo, %{tags: [tag_2.id]})
    Brando.Repo.update!(changeset)
    photo = Brando.Repo.get(Photo, photo.id) |> Brando.Repo.preload(:tags)

    assert photo.tags == [tag_2]
  end

  test "custom function to lookup collection", %{tag_1: tag_1} do
    # Preset ids as strings for demonstration
    tag_id = to_string(tag_1.id)
    changeset = Photo.custom_function_changeset(%Photo{}, %{tags: [tag_id]})

    photo = Brando.Repo.insert!(changeset)
    photo = Brando.Repo.get(Photo, photo.id) |> Brando.Repo.preload(:tags)

    assert photo.tags == [tag_1]
  end

  test "leave association untouched if param not provided", %{tag_1: tag_1} do
    changeset = Photo.changeset(%Photo{}, %{tags: [tag_1.id]})
    photo = Brando.Repo.insert!(changeset)
    photo = Brando.Repo.get(Photo, photo.id) |> Brando.Repo.preload(:tags)

    assert photo.tags == [tag_1]

    changeset = Photo.changeset(photo, %{})
    Brando.Repo.update!(changeset)
    photo = Brando.Repo.get(Photo, photo.id) |> Brando.Repo.preload(:tags)

    assert photo.tags == [tag_1]
  end

  test "handles empty string amongst model id's", %{tag_1: tag_1} do
    changeset = Photo.changeset(%Photo{}, %{tags: [tag_1.id, ""]})

    photo = Brando.Repo.insert!(changeset)
    photo = Brando.Repo.get(Photo, photo.id) |> Brando.Repo.preload(:tags)

    assert photo.tags == [tag_1]
  end

  test "normalizes blank and duplicate IDs from atom-keyed params", %{tag_1: tag_1, tag_2: tag_2} do
    changeset = Photo.changeset(%Photo{}, %{tags: [tag_1.id, "", nil, tag_1.id, tag_2.id]})

    assert changeset.valid?
    assert Enum.map(Changeset.get_change(changeset, :tags), & &1.data.id) == [tag_1.id, tag_2.id]
  end

  test "rejects malformed ID collections" do
    for malformed_ids <- [123, [1, %{id: 2}]] do
      changeset = Photo.changeset(%Photo{}, %{tags: malformed_ids})

      refute changeset.valid?
      assert {"is invalid", [validation: :cast]} = changeset.errors[:tags]
    end
  end

  test "rejects IDs the lookup cannot resolve" do
    missing_id = System.unique_integer([:positive]) + 1_000_000
    changeset = Photo.changeset(%Photo{}, %{"tags" => [missing_id]})

    refute changeset.valid?
    assert {"is invalid", [validation: :cast]} = changeset.errors[:tags]
  end

  test "required collections reject blank ID sentinels before lookup" do
    changeset = Changeset.cast(%Photo{}, %{tags: [nil, ""]}, [])

    result =
      Brando.M2M.cast_collection(
        changeset,
        :tags,
        fn _ids -> flunk("blank IDs must not reach the lookup") end,
        true
      )

    refute result.valid?
    assert {"can't be blank", [validation: :required]} = result.errors[:tags]
  end
end
