defmodule Brando.Trait.Translatable do
  use Brando.Trait

  def generate_code(parent_module) do
    quote generated: true do
      parent_module = unquote(parent_module)
      parent_table_name = @table_name

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

          # field :creator_id, references(:users)
          # has_many :task_links, TaskLinks, foreign_key: :task_id
        end

        def delete(id, parent_id) do
          Brando.repo().delete_all(
            from q in __MODULE__,
              where: q.entry_id == ^id and q.linked_entry_id == ^parent_id,
              or_where: q.entry_id == ^parent_id and q.linked_entry_id == ^id
          )
        end
      end
    end
  end

  attributes do
    attribute :language, :language, required: true
  end

  relations do
    relation :alternates, :has_many, module: :alternates
  end
end
