defmodule Brando.M2MTest do
  use ExUnit.Case, async: true
  doctest Brando.M2M

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
      |> Brando.M2M.cast_collection(:tags, Brando.repo(), Tag)
    end

    def custom_function_changeset(struct, params \\ %{}) do
      struct
      |> cast(params, ~w())
      |> Brando.M2M.cast_collection(:tags, fn ids ->
        # Convert Strings back to Integers for demonstration
        ids = Enum.map(ids, &String.to_integer/1)

        Brando.repo().all(from t in Tag, where: t.id in ^ids)
      end)
    end
  end

  setup do
    # Explicitly get a connection before each test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Brando.repo())

    tag_1 = Brando.repo().insert!(%Tag{})
    tag_2 = Brando.repo().insert!(%Tag{})

    {:ok, [tag_1: tag_1, tag_2: tag_2]}
  end

  test "association for new model", %{tag_1: tag_1} do
    changeset = Photo.changeset(%Photo{}, %{tags: [tag_1.id]})

    photo = Brando.repo().insert!(changeset)
    photo = Brando.repo().get(Photo, photo.id) |> Brando.repo().preload(:tags)

    assert photo.tags == [tag_1]
  end

  test "association for existing model", %{tag_1: tag_1, tag_2: tag_2} do
    changeset = Photo.changeset(%Photo{}, %{tags: [tag_1.id]})
    photo = Brando.repo().insert!(changeset)

    changeset = Photo.changeset(photo, %{tags: [tag_2.id]})
    Brando.repo().update!(changeset)
    photo = Brando.repo().get(Photo, photo.id) |> Brando.repo().preload(:tags)

    assert photo.tags == [tag_2]
  end

  test "custom function to lookup collection", %{tag_1: tag_1} do
    # Preset ids as strings for demonstration
    tag_id = to_string(tag_1.id)
    changeset = Photo.custom_function_changeset(%Photo{}, %{tags: [tag_id]})

    photo = Brando.repo().insert!(changeset)
    photo = Brando.repo().get(Photo, photo.id) |> Brando.repo().preload(:tags)

    assert photo.tags == [tag_1]
  end

  test "leave association untouched if param not provided", %{tag_1: tag_1} do
    changeset = Photo.changeset(%Photo{}, %{tags: [tag_1.id]})
    photo = Brando.repo().insert!(changeset)
    photo = Brando.repo().get(Photo, photo.id) |> Brando.repo().preload(:tags)

    assert photo.tags == [tag_1]

    changeset = Photo.changeset(photo, %{})
    Brando.repo().update!(changeset)
    photo = Brando.repo().get(Photo, photo.id) |> Brando.repo().preload(:tags)

    assert photo.tags == [tag_1]
  end

  test "handles empty string amongst model id's", %{tag_1: tag_1} do
    changeset = Photo.changeset(%Photo{}, %{tags: [tag_1.id, ""]})

    photo = Brando.repo().insert!(changeset)
    photo = Brando.repo().get(Photo, photo.id) |> Brando.repo().preload(:tags)

    assert photo.tags == [tag_1]
  end
end
