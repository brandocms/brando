defmodule Brando.Images.SourceTest do
  # Where an image's file came from, as the Figma import records it and
  # read_frame looks it up.
  use Brando.ConnCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Images.Image
  alias Brando.Images.Source
  alias Brando.Repo

  defp image!(attrs \\ []), do: Factory.insert(:image, attrs)

  defp rows(image),
    do:
      Repo.all(
        from(s in Source,
          where: s.image_id == ^image.id,
          select: {s.ref, s.variant, s.config_target},
          order_by: [s.ref, s.variant]
        )
      )

  defp lookup(keys, target \\ "default") do
    reader = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    Source.images("figma", keys, target, reader)
  end

  test "a picture is recorded once per image and variant, upright included, and may have several images" do
    [first, second] = [image!(), image!()]

    for _twice <- 1..2 do
      Source.record(first, "figma", "p", nil, "default")
      Source.record(first, "figma", "p", "90", "default")
    end

    Source.record(second, "figma", "p", nil, "default")

    assert rows(first) == [{"p", "90", "default"}, {"p", nil, "default"}]
    assert rows(second) == [{"p", nil, "default"}]
  end

  test "the lowest id of the images out of the trash, recorded for the config, by ref and variant" do
    [first, second, third] = [image!(), image!(), image!()]

    for image <- [third, second, first], do: Source.record(image, "figma", "p", nil, "default")
    Source.record(third, "figma", "p", "90", "default")
    Source.record(image!(config_target: "other"), "figma", "q", nil, "other")

    assert lookup([{"p", nil}, {"p", "90"}, {"q", nil}, {"r", nil}]) ==
             %{{"p", nil} => first.id, {"p", "90"} => third.id}

    assert lookup([{"p", "90"}]) == %{{"p", "90"} => third.id}

    Repo.soft_delete!(first)
    assert lookup([{"p", nil}]) == %{{"p", nil} => second.id}
    assert lookup([]) == %{}
  end

  test "a row is not written once another file took the image the import stored or reused" do
    reused = image!(content_hash: "a-hash")
    # A replacement commits another picture's file onto the image between
    # the import's reuse and its record
    Repo.update_all(from(i in Image, where: i.id == ^reused.id), set: [content_hash: "another-hash"])

    assert :ok = Source.record(reused, "figma", "p", nil, "default")
    assert rows(reused) == []

    assert :ok = Source.record(%{reused | content_hash: "another-hash"}, "figma", "p", nil, "default")
    assert rows(reused) == [{"p", nil, "default"}]
  end

  test "a row that cannot be written inside a transaction leaves the transaction to go on" do
    image = image!()
    table = ~s("#{Brando.Tenant.current_prefix() || "public"}".images_sources)

    Repo.repo().query!("""
    CREATE FUNCTION pg_temp.refuse_b() RETURNS trigger AS $$
    BEGIN IF NEW.ref = 'b' THEN RAISE EXCEPTION 'refused'; END IF; RETURN NEW; END $$ LANGUAGE plpgsql
    """)

    Repo.repo().query!(
      "CREATE TRIGGER refuse_b BEFORE INSERT ON #{table} FOR EACH ROW EXECUTE FUNCTION pg_temp.refuse_b()"
    )

    assert {:ok, :done} =
             Repo.transaction(fn ->
               assert :error = Source.record(image, "figma", "b", nil, "default")
               assert :ok = Source.record(image, "figma", "c", nil, "default")
               :done
             end)

    assert rows(image) == [{"c", nil, "default"}]
  end

  test "the image that took another's file takes its sources, for its own config, and drops its own" do
    old = image!(config_target: "portraits")
    new = image!()
    Source.record(old, "figma", "a", nil, "portraits")
    Source.record(new, "figma", "b", nil, "default")
    Source.record(new, "figma", "b", "90", "default")

    assert :ok = Source.hand_over(new, old)

    assert rows(old) == [{"b", "90", "portraits"}, {"b", nil, "portraits"}]
    assert rows(new) == []
    assert %Image{} = Repo.get!(Image, old.id)
  end
end
