defmodule Brando.Repo.Migrations.Brando202AddPublicProfileToUsers do
  use Ecto.Migration

  @moduledoc """
  A user's public profile: a job title and links to their pages elsewhere.
  Both are optional, and only reach a page's JSON-LD when a blueprint maps the
  user as an author (`field :author, :person, & &1.creator`), as the
  `jobTitle` and `sameAs` of their `Person`.

  Users live in the `public` schema only.
  """

  def up do
    alter table(:users, prefix: "public") do
      add_if_not_exists :job_title, :text
      add_if_not_exists :same_as, {:array, :string}, default: []
    end
  end

  def down do
    alter table(:users, prefix: "public") do
      remove_if_exists :job_title, :text
      remove_if_exists :same_as, {:array, :string}
    end
  end
end
