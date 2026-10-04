defmodule BrandoIntegration.Repo.Migrations.AddInlineRowsFixture do
  use Ecto.Migration

  # E2E fixture: `E2eProject.Projects.InlineRow`, one of every inline input
  def change do
    create table(:projects_inline_rows) do
      add :client_id, references(:projects_clients, on_delete: :delete_all)
      add :sequence, :integer
      add :status, :integer
      add :title, :text
      add :slug, :text
      add :key, :text
      add :notes, :text
      add :email, :text
      add :phone, :text
      add :amount, :integer
      add :starts_on, :date
      add :starts_at, :utc_datetime
      add :color, :text
      add :featured, :boolean, default: false
      add :confirmed, :boolean, default: false
      add :kind, :text
      add :size, :text
      add :aliases, {:array, :text}
      add :cover_id, references(:images, on_delete: :nilify_all)
      add :attachment_id, references(:files, on_delete: :nilify_all)
      add :clip_id, references(:videos, on_delete: :nilify_all)
    end

    create index(:projects_inline_rows, [:client_id])
  end
end
