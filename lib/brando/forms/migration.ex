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

  # The site's wording around its forms (`Brando.Forms.Messages`): one row,
  # each message a map of language → text.
  def messages_up(prefix \\ nil) do
    create table(:forms_messages, prefix: prefix) do
      for key <- ~w(submit_label success_message failure_message rate_limited spam_check required unticked
                    none_chosen invalid_email invalid_number invalid_date invalid_choice too_long)a,
          do: add(key, :map)

      timestamps()
    end
  end

  def messages_down(prefix \\ nil) do
    drop table(:forms_messages, prefix: prefix)
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

  # Who a form's submissions are emailed to, the confirmation sent to the
  # visitor, where the visitor goes once it is sent, and how long its
  # submissions are kept.
  def settings_up(prefix \\ nil) do
    alter table(:forms, prefix: prefix) do
      add :recipients, :jsonb, null: false, default: fragment("'[]'::jsonb")
      add :subject, :text
      add :confirmation, :boolean, null: false, default: false
      add :confirmation_subject, :text
      add :confirmation_message, :text
      add :redirect_url, :text
      add :retention_days, :integer
    end
  end

  def settings_down(prefix \\ nil) do
    alter table(:forms, prefix: prefix) do
      remove :recipients
      remove :subject
      remove :confirmation
      remove :confirmation_subject
      remove :confirmation_message
      remove :redirect_url
      remove :retention_days
    end
  end

  # Whether a submission's notification went out: queued, sent, or why not.
  def shared_status_up do
    alter table(:forms_submissions, prefix: "public") do
      add :queued_at, :utc_datetime_usec
      add :sent_at, :utc_datetime_usec
      add :send_error, :text
    end
  end

  def shared_status_down do
    alter table(:forms_submissions, prefix: "public") do
      remove :queued_at
      remove :sent_at
      remove :send_error
    end
  end
end
