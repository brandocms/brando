defmodule Brando.Blueprint.TraitTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Blueprint.Attribute
  alias Brando.Blueprint.Relation
  alias Brando.Trait
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

  describe "villain trait" do
    test "exposes attributes" do
      attrs = [
        %Brando.Blueprint.Attribute{name: :data, type: :villain},
        %Brando.Blueprint.Attribute{name: :bio_data, type: :villain}
      ]

      assert Trait.Villain.all_trait_attributes(attrs, nil, nil) == [
               %Brando.Blueprint.Attribute{name: :html, opts: %{}, type: :text},
               %Brando.Blueprint.Attribute{name: :bio_html, opts: %{}, type: :text}
             ]
    end

    test "adds _html field" do
      assert :html in Brando.TraitTest.Project.__schema__(:fields)
      assert :bio_html in Brando.TraitTest.Project.__schema__(:fields)
    end

    test "changeset mutator" do
      bio_data = [
        %{
          "data" => %{
            "extensions" => [],
            "text" => "Some glorious text",
            "type" => "paragraph"
          },
          "type" => "text"
        }
      ]

      mutated_cs =
        Brando.TraitTest.Project.changeset(
          %Brando.TraitTest.Project{},
          %{
            title: "my title!",
            bio_data: bio_data,
            data: bio_data,
            language: "en"
          },
          %{id: 1}
        )

      assert mutated_cs.valid?
      assert mutated_cs.changes.creator_id == 1
      assert mutated_cs.changes.title == "my title!"
      assert mutated_cs.changes.html == "<div class=\"paragraph\">Some glorious text</div>"
      assert mutated_cs.changes.bio_html == "<div class=\"paragraph\">Some glorious text</div>"
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
               Brando.Content.Module,
               Brando.Content.Section,
               Brando.Image,
               Brando.ImageCategory,
               Brando.ImageSeries,
               Brando.MigrationTest.Person,
               Brando.MigrationTest.Profile,
               Brando.MigrationTest.Project,
               Brando.Pages.Fragment,
               Brando.Pages.Page,
               Brando.Users.User
             ]
    end
  end
end
