defmodule BrandoIntegration.Repo.Migrations.GrantPublishingConfigure do
  use Ecto.Migration

  # Mirrors the brando_249 upgrade migration for the test schema.
  @moduledoc """
  Gives `brando.publishing.configure` to every group that may build, deploy
  or schedule; `down` leaves the grants.
  """

  def up do
    execute("""
    INSERT INTO authorization_group_permissions (group_id, permission_key)
    SELECT DISTINCT group_id, 'brando.publishing.configure'
    FROM authorization_group_permissions
    WHERE permission_key IN ('brando.publishing.build', 'brando.publishing.deploy', 'brando.publishing.schedule')
    ON CONFLICT DO NOTHING
    """)
  end

  def down, do: :ok
end
