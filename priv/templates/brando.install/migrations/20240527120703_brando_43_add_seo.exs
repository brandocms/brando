defmodule Brando.Migrations.AddSEO do
  use Ecto.Migration
  use Brando.Sequence.Migration
  import Ecto.Query

  def change do
    create table(:sites_seo) do
      add :fallback_meta_description, :text
      add :fallback_meta_title, :text
      add :fallback_meta_image, :jsonb
      add :base_url, :text
      add :robots, :text
      add :redirects, :map
      timestamps()
    end

    flush()

    # migrate values from identity
    identity_query =
      from identity in "sites_identity",
        select: %{
          description: identity.description,
          title: identity.title,
          image: identity.image,
          url: identity.url
        }, limit: 1

    identity = Brando.repo().one(identity_query)

    if identity do
      robots = """
      User-agent: *
      Disallow: /admin/
      """
      seo = %{
        fallback_meta_title: identity.title,
        fallback_meta_image: identity.image,
        fallback_meta_description: identity.description,
        base_url: identity.url,
        robots: robots,
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      Brando.repo().insert_all("sites_seo", [seo])
    end

    flush()

    alter table(:sites_identity) do
      remove :image
      remove :description
      remove :url
    end
  end
end
