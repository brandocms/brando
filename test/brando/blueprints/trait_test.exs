defmodule Brando.Blueprint.TraitTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Blueprint.Attribute
  alias Brando.Blueprint.Relation
  alias Brando.Trait
  alias Brando.Users.User

  describe "creator trait" do
    test "exposes relationship" do
      assert Trait.Creator.trait_relations(nil, nil, nil) == [
               %Relation{
                 name: :creator,
                 opts: %{module: User, required: true},
                 type: :belongs_to
               }
             ]
    end
  end

  describe "status trait" do
    test "exposes attribute" do
      assert Trait.Status.all_trait_attributes(nil, nil, nil) == [
               %Attribute{
                 name: :status,
                 opts: %{required: true},
                 type: :status
               }
             ]
    end
  end

  describe "sequence trait" do
    test "exposes attribute" do
      assert Trait.Sequenced.all_trait_attributes(nil, nil, nil) == [
               %Attribute{
                 name: :sequence,
                 opts: %{default: 0},
                 type: :integer
               }
             ]
    end
  end

  describe "language trait" do
    test "adds language field" do
      assert :language in Brando.TraitTest.Project.__schema__(:fields)

      {:parameterized, Ecto.Enum,
       %{
         on_cast: %{"en" => :en, "no" => :no},
         on_load: %{"en" => :en, "no" => :no},
         on_dump: %{en: "en", no: "no"},
         type: :string,
         mappings: [no: "no", en: "en"]
       }}
    end
  end

  describe "implementations" do
    test "list" do
      assert Enum.sort(Trait.list_implementations(Brando.Trait.SoftDelete)) == [
               Brando.BlueprintTest.Project,
               Brando.Content.Container,
               Brando.Content.Module,
               Brando.Content.Palette,
               Brando.Content.Template,
               Brando.Files.File,
               Brando.Images.Gallery,
               Brando.Images.Image,
               Brando.MigrationTest.Profile,
               Brando.MigrationTest.Project,
               Brando.Pages.Fragment,
               Brando.Pages.Page,
               Brando.Persons.Person,
               Brando.Users.User,
               Brando.Videos.Video
             ]
    end
  end
end
