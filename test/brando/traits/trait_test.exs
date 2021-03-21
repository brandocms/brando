defmodule Brando.Blueprint.TraitTest do
  use ExUnit.Case
  alias Brando.Traits
  alias Brando.Pages.Page
  alias Brando.Users.User

  defmodule Project do
    use Brando.Blueprint

    @application "Brando"
    @domain "TraitTest"
    @schema "Project"
    @singular "project"
    @plural "projects"

    trait Brando.Traits.Sequence

    attributes do
      attribute :title, :text
    end
  end

  describe "creator trait" do
    test "exposes relationship" do
      assert Traits.Creator.__relations__() == [
               %{
                 name: :creator,
                 opts: [module: User, required: true],
                 type: :belongs_to
               }
             ]
    end

    test "mutates changeset" do
      changeset = Page.changeset(%Page{}, %{title: "Iggy Pop"})
      mutated_changeset = Traits.Creator.changeset_mutator(nil, changeset, %{id: 1})
      assert mutated_changeset.changes.creator_id == 1
    end
  end

  describe "status trait" do
    test "exposes attribute" do
      assert Traits.Status.__attributes__() == [
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
      assert Traits.Sequence.__attributes__() == [
               %{
                 name: :sequence,
                 opts: [default: 0],
                 type: :integer
               }
             ]
    end

    test "injects sequence/2" do
      assert __MODULE__
    end
  end
end
