defmodule Brando.Trait do
  @type changeset :: Ecto.Changeset.t()
  @type entry :: map()
  @type user :: Brando.Users.User.t()

  @callback changeset_mutator(module, changeset, user) :: changeset

  defmacro __using__(_) do
    quote do
      @behaviour Brando.Trait
      import Brando.Blueprint

      def changeset_mutator(_module, changeset, _user), do: changeset
      defoverridable changeset_mutator: 3

      def __attributes__, do: []
      defoverridable __attributes__: 0

      def __relations__, do: []
      defoverridable __relations__: 0
    end
  end

  def run_changeset_mutators(changeset, module, traits, user) do
    Enum.reduce(traits, changeset, fn trait, updated_changeset ->
      trait.changeset_mutator(module, updated_changeset, user)
    end)
  end

  def get_relations(nil), do: []

  def get_relations(traits) do
    Enum.reduce(traits, [], fn trait, rf ->
      trait.__relations__() ++ rf
    end)
  end

  def get_attributes(nil), do: []

  def get_attributes(traits) do
    require Logger
    Logger.error("==> here we ask for trait.__attributes__()")

    Enum.reduce(traits, [], fn trait, rf ->
      trait.__attributes__() ++ rf
    end)
  end
end
