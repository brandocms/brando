defmodule Brando.Repo.Migrations.NilifyAssetFksInTestSchemas do
  @moduledoc """
  Aligns the test fixtures' asset foreign keys with what real applications get.

  Every image and file asset FK in a consuming app is created with
  `on_delete: :nilify_all` — `brando_80_extract_embeds_one_image_fields` and
  `brando_92_extract_files_embeds_one` add them that way for every blueprint
  plus `Page`, `User`, `Identity` and `SEO`. Seven columns in the monolithic
  test migration were declared as a bare `references(:images)`/`references(:files)`,
  which Postgres defaults to `NO ACTION`.

  That drift is not cosmetic. `Brando.SoftDelete.Query.clean_up_soft_deletions/0`
  purges soft-deleted rows with `Repo.delete_all`, so against these fixtures a
  soft-deleted image that any page still pointed at raised
  `(foreign_key_violation) pages_meta_image_id_fkey` instead of nilifying the
  reference. Any asset-lifecycle test written against the old fixtures would have
  pinned behaviour production does not have.
  """
  use Ecto.Migration

  @image_fks [
    {:users, :avatar_id},
    {:pages, :meta_image_id},
    {:projects, :cover_id},
    {:projects, :cover_cdn_id},
    {:sites_identities, :logo_id},
    {:sites_seos, :fallback_meta_image_id}
  ]

  @file_fks [{:projects, :pdf_id}]

  def change do
    for {table, column} <- @image_fks do
      alter table(table) do
        modify column, references(:images, on_delete: :nilify_all), from: references(:images)
      end
    end

    for {table, column} <- @file_fks do
      alter table(table) do
        modify column, references(:files, on_delete: :nilify_all), from: references(:files)
      end
    end
  end
end
