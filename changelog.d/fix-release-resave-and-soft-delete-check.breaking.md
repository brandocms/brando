- An application whose Repo lacks `use Brando.SoftDelete.Repo` no longer boots, since it cannot delete or restore anything: boot stops with an error naming the line to add.
  Add `use Brando.SoftDelete.Repo` after `use Ecto.Repo` in the application's Repo; `mix igniter.upgrade brando` and `mix brando.migrate55` add it.
