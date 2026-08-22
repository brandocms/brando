defmodule Brando.Repo.Migrations.Brando165AddLastSeenToUsers do
  use Ecto.Migration

  # `last_login` had been carrying two meanings: the login controller wrote it
  # on sign-in, and the presence layer wrote it again whenever a user's last
  # admin session went away. The admin's presence modal reads it as "last seen",
  # which is only true of the second writer — and on a site where nobody stays
  # logged out for long, a remembered session means the first writer may not
  # fire for months.
  #
  # Splitting them gives each column one writer and one meaning.
  #
  # `:naive_datetime` to match `last_login`: both are written with
  # `NaiveDateTime.utc_now/0` and read back through
  # `DateTime.from_naive!(…, "Etc/UTC")`.
  def up do
    alter table(:users, prefix: "public") do
      add_if_not_exists :last_seen, :naive_datetime
    end

    # Seed from `last_login` rather than leaving it null. Every value already in
    # that column is either a login or a departure, and both are times the user
    # was demonstrably here — a strictly better answer than blanking the field
    # for every existing user on upgrade.
    execute """
    UPDATE public.users SET last_seen = last_login WHERE last_seen IS NULL
    """
  end

  def down do
    alter table(:users, prefix: "public") do
      remove_if_exists :last_seen, :naive_datetime
    end
  end
end
