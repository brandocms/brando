defmodule Brando.Trait.Translatable do
  use Brando.Trait

  def generate_code(parent_module, config) do
    quote generated: true do
      parent_module = unquote(parent_module)
      parent_table_name = @table_name
      @translatable_alternates Keyword.get(unquote(config), :alternates, true)

      def has_alternates?, do: @translatable_alternates

      if @translatable_alternates do
        relations do
          relation :alternates, :has_many, module: :alternates
        end

        defmodule Alternate do
          use Ecto.Schema
          import Ecto.Query

          schema "#{parent_table_name}_alternates" do
            Ecto.Schema.belongs_to(
              :entry,
              parent_module
            )

            Ecto.Schema.belongs_to(
              :linked_entry,
              parent_module
            )

            Ecto.Schema.timestamps()
          end

          def changeset(struct, params \\ %{}) do
            Ecto.Changeset.cast(struct, params, [:entry_id, :linked_entry_id])
          end

          def add(id, parent_id) do
            changesets = [
              changeset(%__MODULE__{}, %{"entry_id" => id, "linked_entry_id" => parent_id}),
              changeset(%__MODULE__{}, %{"entry_id" => parent_id, "linked_entry_id" => id})
            ]

            Enum.each(changesets, &Brando.repo().insert!(&1, []))

            Brando.Cache.Query.evict_entry(unquote(parent_module), id)
            Brando.Cache.Query.evict_entry(unquote(parent_module), parent_id)

            :ok
          end

          def delete(id, parent_id) do
            res =
              Brando.repo().delete_all(
                from q in __MODULE__,
                  where: q.entry_id == ^id and q.linked_entry_id == ^parent_id,
                  or_where: q.entry_id == ^parent_id and q.linked_entry_id == ^id
              )

            Brando.Cache.Query.evict_entry(unquote(parent_module), id)
            Brando.Cache.Query.evict_entry(unquote(parent_module), parent_id)

            res
          end
        end
      end
    end
  end

  attributes do
    attribute :language, :language, required: true
  end
end
