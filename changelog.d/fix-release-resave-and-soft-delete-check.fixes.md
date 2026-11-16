- A soft delete or restore through a Repo without `use Brando.SoftDelete.Repo` raises an error that names the line to add, where it said the Repo module was not available, and the System check reports such a Repo as an error.

- `mix brando.install` adds `use Brando.SoftDelete.Repo` to the application's Repo, without which every delete fails.
