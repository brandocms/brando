defmodule Brando.Repo.Migrations.BlocksUniqueUID do
  use Ecto.Migration
  import Ecto.Query

  def change do
    # recreate all blocks uids, just to be safe against unique_violation from old stale data
    Brando.Repo.transaction(fn ->
      Brando.Repo.all(from cb in "content_blocks", select: %{id: cb.id})
      |> Enum.each(fn content_block ->
        new_uid = Brando.Utils.generate_uid()
        Brando.Repo.update_all(
          from(cb in "content_blocks", where: cb.id == ^content_block.id),
          set: [uid: new_uid]
        )
      end)
    end)

    flush()

    create unique_index(:content_blocks, [:uid])
  end
end
