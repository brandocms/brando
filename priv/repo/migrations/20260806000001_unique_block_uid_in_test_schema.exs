defmodule Brando.Repo.Migrations.UniqueBlockUidInTestSchema do
  @moduledoc """
  Adds the `content_blocks.uid` unique index the test fixtures were missing.

  `Brando.Content.Block.block_changeset/3` declares `unique_constraint(:uid)`,
  and consuming applications back it with a real index from
  `brando_123_blocks_uid_constraint`. The monolithic test migration never got
  one, so `unique_constraint/2` had nothing to translate and two root blocks
  could be saved under the same uid without complaint.

  A uid is the block's identity everywhere it matters — the op store keys on it,
  the block component's DOM id is `block-<uid>`, and block recovery keys on
  `entry_block_form-<uid>`. Two blocks sharing one is not a cosmetic problem, so
  a test fixture that allows it cannot be used to reason about the save path.

  ## This migration assumes there are no duplicate uids yet

  Unlike its production counterpart, it has no dedupe step: `brando_123`
  regenerates every block's uid first, because it runs against real customer
  databases that predate the constraint. This one does not, and that is a
  deliberate difference — the databases it runs against are disposable.

  It matters because `priv/repo/migrations` is **symlinked into `e2e/`**, so
  this also migrates the long-lived e2e database, which has been accumulating
  blocks without the constraint. It was validated on a `--reset` run
  (drop → rollback to baseline → forward → reseed), where the table is empty and
  the index always builds.

  If you hit `ERROR 23505 (unique_violation) ... content_blocks_uid_index` while
  migrating without `--reset`, nothing is broken: the existing database has
  duplicate uids from before the constraint. Re-run with
  `./test_e2e.sh --reset`, or dedupe by hand the way `brando_123` does.
  """
  use Ecto.Migration

  def change do
    create unique_index(:content_blocks, [:uid])
  end
end
