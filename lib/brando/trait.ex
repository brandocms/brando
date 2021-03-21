defmodule Brando.Trait do
  @type changeset :: Ecto.Changeset.t()
  @type entry :: map()
  @type user :: Brando.Users.User.t()

  @callback changeset_mutator(module, changeset, user) :: changeset

  defmacro __using__(_) do
    quote location: :keep do
      @before_compile Brando.Trait
      @behaviour Brando.Trait
      import Brando.Trait
      import Brando.Blueprint.DataLayer

      def changeset_mutator(_module, changeset, _user), do: changeset
      defoverridable changeset_mutator: 3
    end
  end

  defmacro __before_compile__(_) do
    quote do
      if Module.get_attribute(__MODULE__, :attrs) do
        def __attributes__ do
          @attrs
        end
      else
        def __attributes__ do
          []
        end
      end

      if Module.get_attribute(__MODULE__, :relations) do
        def __relations__ do
          @relations
        end
      else
        def __relations__ do
          []
        end
      end
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
    Enum.reduce(traits, [], fn trait, rf ->
      trait.__attributes__() ++ rf
    end)
  end
end
