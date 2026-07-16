defmodule Brando.Trait.Translatable.Compiler do
  @moduledoc false

  @doc false
  def generate_code(parent_module, config) do
    quote generated: true do
      parent_module = unquote(parent_module)
      parent_table_name = @table_name
      @translatable_alternates Keyword.get(unquote(config), :alternates, true)

      def has_alternates?, do: @translatable_alternates

      attributes do
        attribute :language, :language, required: true
      end

      if @translatable_alternates do
        relations do
          relation :alternates, :has_many, module: :alternates
        end

        defmodule Alternate do
          use Ecto.Schema
          import Ecto.Query

          alias Brando.Cache.Query, as: CacheQuery
          alias Ecto.Schema

          schema "#{parent_table_name}_alternates" do
            Schema.belongs_to(
              :entry,
              parent_module
            )

            Schema.belongs_to(
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

            Enum.each(changesets, &Brando.Repo.insert!(&1, []))

            CacheQuery.evict_entry(unquote(parent_module), id)
            CacheQuery.evict_entry(unquote(parent_module), parent_id)

            :ok
          end

          def delete(id, parent_id) do
            res =
              Brando.Repo.delete_all(
                from q in __MODULE__,
                  where: q.entry_id == ^id and q.linked_entry_id == ^parent_id,
                  or_where: q.entry_id == ^parent_id and q.linked_entry_id == ^id
              )

            CacheQuery.evict_entry(unquote(parent_module), id)
            CacheQuery.evict_entry(unquote(parent_module), parent_id)

            res
          end
        end
      end
    end
  end
end
