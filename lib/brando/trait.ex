defmodule Brando.Trait do
  @type changeset :: Ecto.Changeset.t()
  @type entry :: map()
  @type user :: Brando.Users.User.t()
  @type config :: list()

  @callback changeset_mutator(module, config, changeset, user) :: changeset
  @callback trait_attributes() :: list()
  @callback trait_relations() :: list()
  @callback validate(module, config) :: true | no_return

  defmacro __using__(_) do
    quote location: :keep do
      @before_compile Brando.Trait
      @behaviour Brando.Trait
      import Brando.Trait
      import Brando.Blueprint.DataLayer

      def changeset_mutator(_module, _cfg, changeset, _user) do
        require Logger
        Logger.error(inspect(changeset, pretty: true))
        changeset
      end

      defoverridable changeset_mutator: 4

      def validate(_, _), do: true
      defoverridable validate: 2
    end
  end

  defmacro __before_compile__(_) do
    quote do
      if Module.get_attribute(__MODULE__, :attrs) do
        def trait_attributes do
          @attrs
        end
      else
        def trait_attributes do
          []
        end
      end

      if Module.get_attribute(__MODULE__, :relations) do
        def trait_relations do
          @relations
        end
      else
        def trait_relations do
          []
        end
      end
    end
  end

  def run_changeset_mutators(changeset, module, traits, user) do
    Enum.reduce(traits, changeset, fn trait, updated_changeset ->
      cfg = module.__trait__(trait)
      trait.changeset_mutator(module, cfg, updated_changeset, user)
    end)
  end

  def get_relations(nil), do: []

  def get_relations(traits) do
    Enum.reduce(traits, [], fn trait, rf ->
      trait.trait_relations() ++ rf
    end)
  end

  def get_attributes(nil), do: []

  def get_attributes(traits) do
    Enum.reduce(traits, [], fn trait, rf ->
      trait.trait_attributes() ++ rf
    end)
  end
end
