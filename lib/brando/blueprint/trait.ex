defmodule Brando.Blueprint.Trait do
  defmacro trait(name, opts \\ []) do
    quote location: :keep,
          generated: true do
      if unquote(name) == Brando.Trait.Translatable do
        parent_module = __MODULE__
        parent_table_name = @table_name

        defmodule Alternate do
          use Ecto.Schema

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
        end
      end

      Module.put_attribute(__MODULE__, :traits, {unquote(name), unquote(opts)})
    end
  end
end
