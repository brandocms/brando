defmodule Brando.Trait.Translatable.Compiler do
  @moduledoc false

  @doc false
  def generate_code(parent_module, config) do
    quote generated: true do
      @translatable_alternates Keyword.get(unquote(config), :alternates, true)

      @translatable_config Brando.Trait.Translatable.config(unquote(config))
      @translatable_runtime Keyword.get(unquote(config), :runtime_config, false)

      def has_alternates?, do: @translatable_alternates
      def __translatable_runtime__?, do: @translatable_runtime

      if @translatable_runtime do
        # Read from the application's config at runtime, per site: see
        # `Brando.Trait.Translatable.RuntimeConfig`.
        def __translatable_config__,
          do: Brando.Trait.Translatable.RuntimeConfig.get(__MODULE__, @translatable_config)
      else
        def __translatable_config__, do: @translatable_config
      end

      attributes do
        attribute :language, :language, required: true
      end

      unquote(generate_alternates(parent_module))
    end
  end

  defp generate_alternates(parent_module) do
    quote generated: true do
      parent_module = unquote(parent_module)
      parent_table_name = @table_name

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

            Brando.Translations.alternate_added(unquote(parent_module), id, parent_id)

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
