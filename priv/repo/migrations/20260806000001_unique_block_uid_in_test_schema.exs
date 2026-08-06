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
  """
  use Ecto.Migration

  def change do
    create unique_index(:content_blocks, [:uid])
  end
end
