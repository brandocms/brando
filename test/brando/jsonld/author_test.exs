defmodule Brando.JSONLD.AuthorTest do
  use ExUnit.Case, async: true

  alias Brando.JSONLD.Author
  alias Brando.JSONLD.Schema.Person
  alias Brando.JSONLDTest.Contributor
  alias Brando.JSONLDTest.Person, as: PeopleEntry
  alias Brando.Users.User

  @portrait %Brando.Images.Image{
    path: "images/people/ada.jpg",
    sizes: %{"xlarge" => "images/people/xlarge/ada.jpg"},
    width: 900,
    height: 1200
  }

  defp user(attrs \\ []) do
    struct(
      %User{
        id: 12,
        name: "Ada Editor",
        email: "ada@example.test",
        password: "hashed-secret",
        role: :superuser,
        language: "en",
        job_title: "Editor-in-chief",
        same_as: ["https://www.linkedin.com/in/ada", "https://ada.example"],
        avatar: %Ecto.Association.NotLoaded{}
      },
      attrs
    )
  end

  describe "Brando users" do
    test "become a Person with only their public profile" do
      person = Author.build(user(avatar: @portrait))

      assert %Person{} = person
      assert person."@id" =~ ~r"^http://localhost/#/schema/person/[0-9a-f]{16}$"
      assert person.name == "Ada Editor"
      assert person.jobTitle == "Editor-in-chief"
      assert person.sameAs == ["https://www.linkedin.com/in/ada", "https://ada.example"]
      assert person.image.url == "http://localhost/media/images/people/xlarge/ada.jpg"
      assert person.email == nil
      assert person.url == nil
    end

    test "never leak private fields into the JSON" do
      json = user() |> Author.build() |> Brando.JSONLD.to_json()

      refute json =~ "ada@example.test"
      refute json =~ "hashed-secret"
      refute json =~ "superuser"
      refute json =~ "\"12\""
    end

    test "the @id is stable and differs between users" do
      assert Author.build(user())."@id" == Author.build(user(name: "Renamed"))."@id"
      refute Author.build(user())."@id" == Author.build(user(id: 13))."@id"
    end

    test "empty profile fields are left out" do
      person = Author.build(user(job_title: " ", same_as: []))

      assert person.jobTitle == nil
      assert person.sameAs == nil
    end
  end

  describe "People entries" do
    defp ada(attrs \\ []) do
      struct(
        %PeopleEntry{
          id: 3,
          name: "Ada Lovelace",
          slug: "ada",
          job_title: "Analyst",
          email: "private@example.test",
          same_as: ["https://en.wikipedia.org/wiki/Ada_Lovelace"],
          portrait: @portrait
        },
        attrs
      )
    end

    test "use the blueprint's own Person mapping, with the profile page as @id" do
      person = Author.build(ada())

      assert person."@id" == "http://localhost/people/ada/#person"
      assert person.url == "http://localhost/people/ada"
      assert person.name == "Ada Lovelace"
      assert person.jobTitle == "Analyst"
      assert person.sameAs == ["https://en.wikipedia.org/wiki/Ada_Lovelace"]
      assert person.image.url == "http://localhost/media/images/people/xlarge/ada.jpg"
      assert person.email == nil
    end

    test "an image that is not preloaded is left out" do
      assert Author.build(ada(portrait: %Ecto.Association.NotLoaded{})).image == nil
    end

    test "without a Person mapping are read by convention" do
      contributor = %Contributor{
        id: 5,
        name: "Grace",
        job_title: "Photographer",
        email: "grace@example.test",
        avatar: @portrait
      }

      person = Author.build(contributor)

      assert person."@id" =~ ~r"^http://localhost/#/schema/person/[0-9a-f]{16}$"
      assert person.name == "Grace"
      assert person.jobTitle == "Photographer"
      assert person.image.url =~ "ada.jpg"
      assert person.url == nil
      assert person.email == nil
    end
  end

  test "lists drop what is missing and repeated" do
    assert [%Person{name: "Ada Editor"}, %Person{name: "Ada Lovelace"}] =
             Author.build([
               user(),
               nil,
               %Ecto.Association.NotLoaded{},
               user(),
               %PeopleEntry{name: "Ada Lovelace", slug: "a"}
             ])

    assert Author.build([nil]) == nil
    assert Author.build(%Ecto.Association.NotLoaded{}) == nil
    assert Author.build(user(name: nil)) == nil
  end

  test "a plain name is a Person without an @id" do
    assert Author.build("Anonymous") == %Person{name: "Anonymous"}
  end
end
