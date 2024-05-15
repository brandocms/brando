defmodule Brando.Trait.Villain do
  @moduledoc """
  Villain parsing
  """
  use Brando.Trait
  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  @impl true
  def validate(module, _config) do
    if Enum.filter(module.__attributes__(), &(&1.type == :villain)) != [] do
      raise Brando.Exception.BlueprintError,
        message: """
        Resource `#{inspect(module)}` is declaring Brando.Trait.Villain, but there are attributes with type `:villain` found.

        Remove your :villain fields from the attributes block

            attributes do
              attribute :data, :villain
            end

        And instead add as a relation

            relations do
              relation :blocks, :has_many, module: :blocks
            end
        """
    end

    if module.__villain_fields__ == [] do
      raise Brando.Exception.BlueprintError,
        message: """
        Resource `#{inspect(module)}` is declaring Brando.Trait.Villain, but there are no relations with module `:blocks` found.

            relations do
              relation :blocks, :has_many, module: :blocks
            end
        """
    end

    true
  end

  # @doc """
  # Generate HTML
  # """
  # @impl true
  # def changeset_mutator(module, _config, changeset, _user, opts) do
  #   opts = Enum.into(opts, %{})
  #   cast_rendered_blocks(changeset, module, opts)
  #   # |> cast_assoc(:book_authors,
  #   #   with: &AuthorBook.changeset/3,
  #   #   sort_param: :authors_order,
  #   #   drop_param: :authors_delete
  #   # )

  #   # case Keyword.get(opts, :skip_villain) do
  #   #   true ->
  #   #     cast_poly(changeset, module.__villain_fields__())

  #   #   _ ->
  #   #     case cast_poly(changeset, module.__villain_fields__()) do
  #   #       %{valid?: true} = casted_changeset ->
  #   #         Enum.reduce(module.__villain_fields__(), casted_changeset, fn vf, mutated_changeset ->
  #   #           Brando.Villain.Schema.generate_html(mutated_changeset, vf.name)
  #   #         end)

  #   #       casted_changeset ->
  #   #         casted_changeset
  #   #     end
  #   # end
  #   changeset
  # end

  # defp cast_rendered_blocks(changeset, _, %{skip_villain: true}) do
  #   changeset
  # end
  # defp cast_rendered_blocks(changeset, module, _) do

  # end

  @impl true
  def generate_code(parent_module, _config) do
    quote generated: true do
      parent_module = unquote(parent_module)
      parent_table_name = @table_name

      defmodule Blocks do
        use Ecto.Schema
        import Ecto.Query

        schema "#{parent_table_name}_blocks" do
          Ecto.Schema.belongs_to(:entry, parent_module)
          Ecto.Schema.belongs_to(:block, Brando.Content.Block, on_replace: :update)
          Ecto.Schema.field(:sequence, :integer)
          Ecto.Schema.field(:marked_as_deleted, :boolean, default: false, virtual: true)
        end

        @parent_table_name parent_table_name
        def changeset(entry_block, attrs, user, recursive? \\ false) do
          entry_block
          |> cast(attrs, [:entry_id, :block_id, :sequence])
          |> Brando.Content.Block.maybe_cast_recursive(recursive?, user)
          |> unique_constraint([:entry, :block],
            name: "#{@parent_table_name}_blocks_entry_id_block_id_index"
          )
        end
      end
    end
  end
end
