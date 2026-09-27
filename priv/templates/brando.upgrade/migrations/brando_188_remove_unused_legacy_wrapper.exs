defmodule Brando.Repo.Migrations.Brando188RemoveUnusedLegacyWrapper do
  use Ecto.Migration
  import Ecto.Query

  @moduledoc """
  Migration 108 always created a "Legacy Content Wrapper" module for wrapping
  old villain blocks, so sites with nothing to migrate offered it to editors
  in the block picker. Soft-delete it where no block uses it; a site that
  wrapped legacy content keeps it.
  """

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    unused =
      from(m in "content_modules",
        as: :module,
        where: m.class == "legacy-content" and is_nil(m.deleted_at),
        where: not exists(from(b in "content_blocks", where: b.module_id == parent_as(:module).id, select: 1)),
        select: m.id
      )

    ids = repo().all(unused)

    if ids != [] do
      repo().update_all(from(m in "content_modules", where: m.id in ^ids), set: [deleted_at: now])
    end
  end

  def down do
  end
end
