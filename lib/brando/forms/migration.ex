defmodule Brando.Forms.Migration do
  @moduledoc false
  use Ecto.Migration

  # Forms are content: one set of tables in each site environment, copied with
  # it when an environment is promoted.
  def content_up(prefix \\ nil) do
    create table(:forms, prefix: prefix) do
      add :title, :text, null: false
      add :key, :text, null: false
      add :intro, :text
      add :submit_label, :text
      add :success_message, :text
      add :language, :text
      add :status, :integer
      add :creator_id, references(:users, prefix: "public", on_delete: :nilify_all)
      add :updated_by_id, references(:users, prefix: "public", on_delete: :nilify_all)
      add :edited_at, :utc_datetime
      timestamps()
    end

    create unique_index(:forms, [:key, :language], prefix: prefix)

    create table(:forms_fields, prefix: prefix) do
      add :uid, :text, null: false
      add :key, :text, null: false
      add :type, :text, null: false
      add :label, :text
      add :placeholder, :text
      add :help_text, :text
      add :default_value, :text
      add :required, :boolean, null: false, default: false
      add :width, :text, null: false, default: "full"
      add :new_row, :boolean, null: false, default: false
      add :option_values, {:array, :text}, null: false, default: []
      add :option_labels, :map, null: false, default: %{}
      add :sequence, :integer
      add :form_id, references(:forms, prefix: prefix, on_delete: :delete_all), null: false
    end

    create index(:forms_fields, [:form_id], prefix: prefix)

    create table(:forms_alternates, prefix: prefix) do
      add :entry_id, references(:forms, prefix: prefix, on_delete: :delete_all)
      add :linked_entry_id, references(:forms, prefix: prefix, on_delete: :delete_all)
      timestamps()
    end

    create unique_index(:forms_alternates, [:entry_id, :linked_entry_id], prefix: prefix)
  end

  def content_down(prefix \\ nil) do
    drop table(:forms_alternates, prefix: prefix)
    drop table(:forms_fields, prefix: prefix)
    drop table(:forms, prefix: prefix)
  end

  # A block var can hold a form, like it holds an image.
  def vars_up(prefix \\ nil) do
    alter table(:content_vars, prefix: prefix) do
      add :form_id, references(:forms, prefix: prefix, on_delete: :nilify_all)
    end

    create index(:content_vars, [:form_id], prefix: prefix)
  end

  def vars_down(prefix \\ nil) do
    alter table(:content_vars, prefix: prefix) do
      remove :form_id
    end
  end

  # Submissions are kept in `public`, scoped by tenant prefix: promoting an
  # environment replaces its schema, and must not take visitors' submissions
  # with it. `form_id` is therefore a plain column, not a foreign key.
  def shared_up do
    create table(:forms_submissions, prefix: "public") do
      add :scope, :text, null: false
      add :form_id, :bigint, null: false
      add :form_key, :text, null: false
      add :language, :text
      add :data, :map, null: false, default: %{}
      add :labels, :map, null: false, default: %{}
      add :url, :text
      add :ip_hash, :text
      add :user_agent, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:forms_submissions, [:scope, :form_key, :inserted_at], prefix: "public")
  end

  def shared_down do
    drop table(:forms_submissions, prefix: "public")
  end
end
