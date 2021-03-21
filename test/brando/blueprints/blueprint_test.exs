defmodule Brando.Blueprint.BlueprintTest do
  use ExUnit.Case

  defmodule Project do
    use Brando.Blueprint

    application "Brando"
    domain "Projects"
    schema "Project"
    singular "project"
    plural "projects"

    trait Brando.Traits.Creator
    trait Brando.Traits.SoftDelete
    trait Brando.Traits.Sequence

    attributes do
      attribute :title, :string
      attribute :slug, :slug, from: :title, required: true
    end

    relations do
    end
  end

  test "naming" do
    assert __MODULE__.Project.__application__() == "Brando"
    assert __MODULE__.Project.__domain__() == "Projects"
    assert __MODULE__.Project.__schema__() == "Project"
    assert __MODULE__.Project.__singular__() == "project"
    assert __MODULE__.Project.__plural__() == "projects"
  end

  test "modules" do
    assert __MODULE__.Project.__modules__(:application) == Brando
    assert __MODULE__.Project.__modules__(:context) == Brando.Projects
    assert __MODULE__.Project.__modules__(:schema) == Brando.Projects.Project
  end

  test "traits" do
    assert __MODULE__.Project.__traits__() == [
             Brando.Traits.Creator,
             Brando.Traits.SoftDelete,
             Brando.Traits.Sequence
           ]
  end

  test "changeset mutators" do
    mutated_cs =
      __MODULE__.Project.test_changeset(%__MODULE__.Project{}, %{title: "my title"}, %{id: 1})

    assert mutated_cs.changes.creator_id == 1
    assert mutated_cs.changes.title == "my title"
  end

  test "__required_attrs__" do
    required_attrs = __MODULE__.Project.__required_attrs__()
    assert required_attrs == [:slug, :creator_id]
  end

  test "__optional_attrs__" do
    optional_attrs = __MODULE__.Project.__optional_attrs__()
    assert optional_attrs == [:title, :deleted_at, :sequence]
  end

  test "attributes" do
    attrs = __MODULE__.Project.__attributes__()

    assert attrs == [
             %{name: :title, opts: [], type: :string},
             %{name: :slug, opts: [from: :title, required: true], type: :slug},
             %{name: :deleted_at, opts: [], type: :datetime},
             %{name: :sequence, opts: [default: 0], type: :integer}
           ]
  end

  test "relations" do
    relations = __MODULE__.Project.__relations__()

    assert relations == [
             %{
               name: :creator,
               opts: [module: Brando.Users.User, required: true],
               type: :belongs_to
             }
           ]
  end

  test "ecto schema" do
    schema = __MODULE__.Project.__schema__(:fields)
    assert schema == [:id, :title, :slug, :deleted_at, :sequence, :creator_id]
  end
end
