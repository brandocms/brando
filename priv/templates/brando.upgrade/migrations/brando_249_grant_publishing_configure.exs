defmodule Brando.Repo.Migrations.Brando249GrantPublishingConfigure do
  use Ecto.Migration

  @moduledoc """
  Gives `brando.publishing.configure` to every group that may build, deploy
  or schedule a static site's builds.

  Saving a site's deployment settings, its SSH key and host keys, and the
  target's review and keep list now take `configure` on publishing, which
  building, deploying and scheduling no longer give. A group that could do
  them before keeps them.

  Only inserts, so it can run twice. `down` leaves the grants: an
  administrator may have given `configure` since, and nothing tells those
  apart. The grants are in the `public` schema only.
  """

  def up do
    execute("""
    INSERT INTO public.authorization_group_permissions (group_id, permission_key)
    SELECT DISTINCT group_id, 'brando.publishing.configure'
    FROM public.authorization_group_permissions
    WHERE permission_key IN ('brando.publishing.build', 'brando.publishing.deploy', 'brando.publishing.schedule')
    ON CONFLICT DO NOTHING
    """)
  end

  def down, do: :ok
end
