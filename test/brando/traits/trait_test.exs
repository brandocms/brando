defmodule Brando.Blueprint.TraitTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Traits
  alias Brando.Users.User

  defmodule Project do
    use Brando.Blueprint

    @application "Brando"
    @domain "Projects"
    @schema "Project"
    @singular "project"
    @plural "projects"

    trait Brando.Traits.Creator
    trait Brando.Traits.Sequence
    trait Brando.Traits.Villain
    trait Brando.Traits.Translatable
    trait Brando.Traits.Unique, attributes: [:title]

    attributes do
      attribute :title, :string
      attribute :data, :villain
      attribute :bio_data, :villain
    end
  end

  describe "creator trait" do
    test "exposes relationship" do
      assert Traits.Creator.trait_relations() == [
               %{
                 name: :creator,
                 opts: [module: User, required: true],
                 type: :belongs_to
               }
             ]
    end
  end

  describe "status trait" do
    test "exposes attribute" do
      assert Traits.Status.trait_attributes() == [
               %{
                 name: :status,
                 opts: [required: true],
                 type: :status
               }
             ]
    end
  end

  describe "sequence trait" do
    test "exposes attribute" do
      assert Traits.Sequence.trait_attributes() == [
               %{
                 name: :sequence,
                 opts: [default: 0],
                 type: :integer
               }
             ]
    end
  end

  describe "villain trait" do
    test "adds _html field" do
      assert :html in __MODULE__.Project.__schema__(:fields)
      assert :bio_html in __MODULE__.Project.__schema__(:fields)
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
        __MODULE__.Project.changeset(
          %__MODULE__.Project{},
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
      assert mutated_cs.changes.html == "Some glorious text"
      assert mutated_cs.changes.bio_html == "Some glorious text"
    end
  end

  describe "language trait" do
    test "adds language field" do
      assert :language in __MODULE__.Project.__schema__(:fields)

      assert __MODULE__.Project.__changeset__()[:language] ==
               {:parameterized, Ecto.Enum,
                %{
                  on_dump: %{en: "en", no: "no"},
                  on_load: %{"en" => :en, "no" => :no},
                  values: [:no, :en]
                }}
    end
  end
end
