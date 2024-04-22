defmodule Brando.Trait.Villain do
  @moduledoc """
  Villain parsing
  """
  use Brando.Trait
  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  # @impl true
  # def trait_attributes(attributes, _assets, _relations) do
  #   attributes
  #   |> Enum.filter(&(&1.type == :villain))
  #   |> Enum.map(fn
  #     %{name: :data} ->
  #       Attributes.build_attr(:html, :text, [])

  #     %{name: data_name} ->
  #       data_name
  #       |> to_string
  #       |> String.replace("_data", "_html")
  #       |> String.to_atom()
  #       |> Attributes.build_attr(:text, [])
  #   end)
  # end

  # @impl true
  # def validate(module, _config) do
  #   if module.__villain_fields__ == [] do
  #     raise ConfigError,
  #       message: """
  #       Resource `#{inspect(module)}` is declaring Brando.Trait.Villain, but there are no attributes of type `:villain` found.

  #           attributes do
  #             attribute :data, :villain
  #           end
  #       """
  #   end

  #   true
  # end

  @doc """
  Generate HTML
  """
  @impl true
  def changeset_mutator(module, _config, changeset, _user, opts) do
    # |> cast_assoc(:book_authors,
    #   with: &AuthorBook.changeset/3,
    #   sort_param: :authors_order,
    #   drop_param: :authors_delete
    # )

    case Keyword.get(opts, :skip_villain) do
      true ->
        cast_poly(changeset, module.__villain_fields__())

      _ ->
        case cast_poly(changeset, module.__villain_fields__()) do
          %{valid?: true} = casted_changeset ->
            Enum.reduce(module.__villain_fields__(), casted_changeset, fn vf, mutated_changeset ->
              Brando.Villain.Schema.generate_html(mutated_changeset, vf.name)
            end)

          casted_changeset ->
            casted_changeset
        end
    end
  end

  defp cast_poly(changeset, villain_fields) do
    Enum.reduce(villain_fields, changeset, fn vf, mutated_changeset ->
      PolymorphicEmbed.cast_polymorphic_embed(mutated_changeset, vf.name)
    end)
  end

  @impl true
  def generate_code(parent_module, _config) do
    quote generated: true do
      parent_module = unquote(parent_module)
      parent_table_name = @table_name

      relations do
        relation :blocks, :has_many, module: :blocks
      end

      defmodule Blocks do
        use Ecto.Schema
        import Ecto.Query

        schema "#{parent_table_name}_blocks" do
          Ecto.Schema.belongs_to(:entry, parent_module)
          Ecto.Schema.belongs_to(:block, Brando.Content.Block, on_replace: :update)
          Ecto.Schema.field(:sequence, :integer)
        end

        @parent_table_name parent_table_name
        def changeset(entry_block, attrs, user, recursive? \\ false) do
          cs = cast(entry_block, attrs, [:entry_id, :block_id, :sequence])

          if recursive? do
            cast_assoc(cs, :block, with: &recursive_block_changeset(&1, &2, user))
          else
            cast_assoc(cs, :block, with: &block_changeset(&1, &2, user))
          end
          |> unique_constraint([:entry, :block],
            name: "#{@parent_table_name}_blocks_entry_id_block_id_index"
          )
        end

        def block_changeset(block, attrs, user) do
          block
          |> cast(attrs, [:description, :uid, :creator_id, :sequence, :parent_id])
          |> cast_assoc(:vars, with: &var_changeset(&1, &2, user))
          |> cast_embed(:refs, with: &ref_changeset(&1, &2, user))
        end

        def recursive_block_changeset(block, attrs, user) do
          block
          |> cast(attrs, [:description, :uid, :creator_id, :sequence, :parent_id])
          |> cast_assoc(:vars, with: &var_changeset(&1, &2, user))
          |> cast_embed(:refs, with: &ref_changeset(&1, &2, user))
          |> cast_assoc(:children, with: &recursive_block_changeset(&1, &2, user))
        end

        def var_changeset(var, attrs, user) do
          cast(var, attrs, [
            :key,
            :value,
            :creator_id,
            :module_id,
            :page_id,
            :block_id,
            :palette_id,
            :image_id,
            :file_id,
            :linked_identifier_id,
            :global_set_id
          ])
        end

        def ref_changeset(ref, attrs, user) do
          require Logger

          Logger.error("""


          ref_changeset
          #{inspect(ref, pretty: true)}


          """)

          ref
          |> cast(attrs, [:name, :description])
          |> PolymorphicEmbed.cast_polymorphic_embed(:data)
        end
      end
    end
  end

  attributes do
    attribute :html, :text
  end
end
