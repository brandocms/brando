defmodule Brando.Repo.Migrations.ExtractEmbedsOneFileFields do
  use Ecto.Migration
  import Ecto.Query

  def change do
    blueprints = Brando.Blueprint.list_blueprints()

    for blueprint <- blueprints,
        %{type: :file, name: field_name} <- Brando.Blueprint.Assets.__assets__(blueprint) do
      # Lookup if we have the old format `field_name` in the fields
      %{columns: existing_columns} =
        Ecto.Adapters.SQL.query!(
          Brando.Repo.repo(),
          "select * from #{blueprint.__schema__(:source)} where false;"
        )

      if to_string(field_name) in existing_columns do
        file_field_query =
          from(t in blueprint.__schema__(:source),
            select: %{
              id: t.id,
              file: field(t, ^field_name),
              inserted_at: t.inserted_at,
              updated_at: t.updated_at
            }
          )

        file_field_query =
          if blueprint.has_trait(Brando.Trait.Creator) do
            from(t in file_field_query, select_merge: %{creator_id: t.creator_id})
          else
            file_field_query
          end

        file_fields =
          file_field_query
          |> Brando.Repo.all()
          |> Enum.reject(&(&1.file == nil))

        field_id_atom = String.to_atom("#{field_name}_id")

        alter table(blueprint.__schema__(:source)) do
          add field_id_atom, references(:files, on_delete: :nilify_all)
        end

        flush()

        config_target = "file:#{inspect(blueprint)}:#{field_name}"

        for file_field <- file_fields do
          file_struct = Jason.decode!(file_field.file)

          new_file = %{
            filesize: file_struct["size"],
            filename: Path.basename(file_struct["path"]),
            mime_type: file_struct["mimetype"],
            cdn: file_struct["cdn"],
            inserted_at: file_field.inserted_at,
            updated_at: file_field.updated_at,
            creator_id: file_field[:creator_id] || 1,
            config_target: config_target
          }

          {_, [%{id: new_file_id}]} =
            Brando.Repo.insert_all("files", [new_file], returning: [:id])

          update_query =
            from(t in blueprint.__schema__(:source),
              where: t.id == ^file_field.id,
              update: [set: [{^field_id_atom, ^new_file_id}]]
            )

          Brando.Repo.update_all(update_query, [])
        end

        alter table(blueprint.__schema__(:source)) do
          remove field_name
        end
      end
    end
  end
end
