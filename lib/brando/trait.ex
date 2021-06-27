defmodule Brando.Trait do
  @moduledoc """
  ## Changeset phase

  If you need your trait's `changeset_mutator` to run before `validate_required`
  when your `changeset` is generated, you can set `@changeset_phase :before_validate_required`
  in your trait. This is useful if you're inserting a required field  into the changeset and
  do not want it erroring out. The default changeset phase is `:after_validate_required`.
  """

  @type changeset :: Ecto.Changeset.t()
  @type entry :: map()
  @type user :: Brando.Users.User.t()
  @type config :: list()
  @type opts :: Keyword.t()

  @callback changeset_mutator(module, config, changeset, user, opts) :: changeset
  @callback trait_attributes(list(), list()) :: list()
  @callback trait_relations(list(), list()) :: list()
  @callback validate(module, config) :: true | no_return

  defmacro __using__(_) do
    defprotocol Module.concat([__CALLER__.module, Implemented]) do
      @doc "Dummy function to ensure implementation"
      def implemented(dummy)
    end

    quote location: :keep do
      @behaviour Brando.Trait

      import Brando.Trait
      import Brando.Blueprint.Attributes
      import Brando.Blueprint.Relations

      @before_compile Brando.Trait
      @changeset_phase :after_validate_required

      # Runs if no mutator is set.
      # NOTE: This does not function as a fallback clause if a mutator is implemented.
      #       In that case you must implement the fallback yourself.
      def changeset_mutator(_module, _cfg, changeset, _user, _opts), do: changeset
      defoverridable changeset_mutator: 5

      def validate(_, _), do: true
      defoverridable validate: 2

      def list_implementations, do: list_implementations(__MODULE__)
    end
  end

  defmacro __before_compile__(_) do
    quote do
      if Module.get_attribute(__MODULE__, :attrs) do
        def trait_attributes(_, _) do
          @attrs
        end

        defoverridable trait_attributes: 2
      else
        def trait_attributes(_, _), do: []
        defoverridable trait_attributes: 2
      end

      if Module.get_attribute(__MODULE__, :relations) do
        def trait_relations(_, _) do
          @relations
        end
      else
        def trait_relations(_, _) do
          []
        end
      end

      def __changeset_phase__ do
        @changeset_phase
      end
    end
  end

  def run_changeset_mutators(changeset, module, traits, user, opts) do
    Enum.reduce(traits, changeset, fn {trait, trait_opts}, updated_changeset ->
      trait.changeset_mutator(module, trait_opts, updated_changeset, user, opts)
    end)
  end

  def split_traits_by_changeset_phase(traits) do
    Enum.split_with(traits, &(elem(&1, 0).__changeset_phase__() == :before_validate_required))
  end

  def get_relations(nil), do: []

  @doc """
  NOTE: This list of attrs and relations does NOT include added
  attributes and relations from other traits, only attrs and relations
  specified directly in the blueprint
  """
  def get_relations(attrs, relations, traits) do
    Enum.reduce(traits, [], fn {trait, _opts}, rf ->
      trait.trait_relations(attrs, relations) ++ rf
    end)
  end

  def get_attributes(nil), do: []

  @doc """
  NOTE: This list of attrs and relations does NOT include added
  attributes and relations from other traits, only attrs and relations
  specified directly in the blueprint
  """
  def get_attributes(attrs, relations, traits) do
    Enum.reduce(traits, [], fn {trait, _opts}, rf ->
      trait.trait_attributes(attrs, relations) ++ rf
    end)
  end

  def list_implementations(trait) do
    {:consolidated, impls} = Module.concat([trait, Implemented]).__protocol__(:impls)
    impls
  end
end
