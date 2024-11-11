defmodule Brando.Repo.Migrations.ExtractEmbedsOneVideoFields do
  use Ecto.Migration
  import Ecto.Query

  def change do
    create table(:videos) do
      add :url, :text
      add :source, :text
      add :filename, :text
      add :remote_id, :text
      add :width, :integer
      add :height, :integer
      add :thumbnail_url, :text
      add :autoplay, :boolean
      add :preload, :boolean
      add :loop, :boolean
      add :controls, :boolean
      add :cdn, :boolean
      add :config_target, :text
      add :creator_id, references(:users, on_delete: :nothing)
      add :cover_image_id, references(:images, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime
      timestamps()
    end

    flush()

    blueprints = Brando.Blueprint.list_blueprints()

    for blueprint <- blueprints,
        %{type: :video, name: field_name} <- blueprint.__assets__() do
      # Lookup if we have the old format `field_name` in the fields
      %{columns: existing_columns} =
        Ecto.Adapters.SQL.query!(
          Brando.Repo.repo(),
          "select * from #{blueprint.__schema__(:source)} where false;"
        )

      if to_string(field_name) in existing_columns do
        video_field_query =
          from(t in blueprint.__schema__(:source),
            select: %{
              id: t.id,
              video: field(t, ^field_name),
              inserted_at: t.inserted_at,
              updated_at: t.updated_at
            }
          )

        video_field_query =
          if blueprint.has_trait(Brando.Trait.Creator) do
            from(t in video_field_query, select_merge: %{creator_id: t.creator_id})
          else
            video_field_query
          end

        video_fields =
          video_field_query
          |> Brando.Repo.all()
          |> Enum.reject(&(&1.video == nil))

        field_id_atom = String.to_atom("#{field_name}_id")

        alter table(blueprint.__schema__(:source)) do
          add field_id_atom, references(:videos, on_delete: :nilify_all)
        end

        flush()

        config_target = "video:#{inspect(blueprint)}:#{field_name}"

        for video_field <- video_fields do
          video_struct =
            video_field.video
            |> Jason.decode!()

          new_video = %{
            url: video_struct["url"],
            source: video_struct["source"],
            filename:
              (video_struct["source"] == :file && Path.basename(video_struct["url"])) || nil,
            remote_id: video_struct["remote_id"],
            width: video_struct["width"],
            height: video_struct["height"],
            thumbnail_url: video_struct["thumbnail_url"],
            autoplay: true,
            preload: true,
            loop: true,
            controls: false,
            inserted_at: video_field.inserted_at,
            updated_at: video_field.updated_at,
            creator_id: video_field[:creator_id] || 1,
            cdn: video_struct["cdn"],
            config_target: config_target
          }

          {_, [%{id: new_video_id}]} =
            Brando.Repo.insert_all("videos", [new_video], returning: [:id])

          update_query =
            from(t in blueprint.__schema__(:source),
              where: t.id == ^video_field.id,
              update: [set: [{^field_id_atom, ^new_video_id}]]
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
