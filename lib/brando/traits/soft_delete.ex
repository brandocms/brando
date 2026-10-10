defmodule Brando.Trait.SoftDelete do
  @moduledoc """
  Adds `deleted_at`

  ### Opts

  - `obfuscated_fields` > Fields that should be changed on deletion to free up
  its name for uniqueness -- for instance a slug field. It will try to reset it
  when restoring.

      trait :soft_delete, obfuscated_fields: [:slug]

  ### Entries in the trash

  A trashed entry keeps its row with `deleted_at` set. Generated list and get
  queries leave it out unless given `with_deleted`, but `Brando.Repo.get/3`,
  `Brando.Repo.all/2`, preloads (unless `hide_deleted`) and revision lookups
  still return it, so code reached from those can act on a trashed entry:

  - A change to it announces nothing: `Brando.ContentEvents` sends only
    `entry.deleted` and `entry.restored` for it (no webhook, no IndexNow).
    Code that tells the outside world of a change by another route checks
    `deleted_at` itself.
  - A revision restore never moves an entry into or out of the trash, and
    keeps the obfuscated fields as the entry has them when the entry or the
    revision is in the trash. A new restore path builds its params with
    `Brando.Revisions.restore_params/2`, which holds that rule.
  """
  use Brando.Trait

  alias Brando.Trait.SoftDelete.Compiler

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)
end
