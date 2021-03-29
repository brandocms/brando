defmodule Brando.Blueprint.ConstraintsTest do
  use ExUnit.Case
  use Brando.ConnCase

  defmodule P1 do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Projects",
      schema: "Project",
      singular: "project",
      plural: "projects"

    attributes do
      attribute :title, :string, unique: true
    end
  end

  test "unique" do
    _cs = __MODULE__.P1.changeset(%__MODULE__.P1{}, %{title: "Hepp"}, %{id: 1})
  end
end
