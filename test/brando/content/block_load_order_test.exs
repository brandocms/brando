defmodule Brando.Content.BlockLoadOrderTest do
  # Refs, vars and children written without a sequence all have 0. They used
  # to come back in Postgres' physical order, which changes whenever a row is
  # rewritten (an update, or space freed by other transactions). In a loaded
  # test run that put a block's "clip" ref before its "info" ref, and
  # set_field_test.exs typed into the wrong one. `:id` breaks the tie.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query

  alias Brando.Pages.Page

  setup do
    c = Brando.ProposalFixtures.context()
    Brando.ProposalFixtures.multi_context(c)
  end

  # Rewrites the first ref of each tie, which moves it behind its sibling on
  # disk without changing anything a reader sees.
  defp rewrite_info_refs do
    Brando.Repo.update_all(from(r in "content_refs", where: r.name == "info"), set: [name: "info"])
  end

  defp ref_names(block), do: Enum.map(block.refs, & &1.name)

  test "refs with the same sequence load in the order they were written", c do
    rewrite_info_refs()

    [_intro, multi] =
      Page.Blocks
      |> where([eb], eb.entry_id == ^c.work.id)
      |> order_by([eb], eb.sequence)
      |> Brando.Repo.all()
      |> Brando.Repo.preload(block: [:refs, children: &Brando.Content.Blocks.preload_child_trees/1])

    # Through the schema's preload order…
    for child <- Brando.Repo.preload(multi.block.children, :refs, force: true),
        do: assert(ref_names(child) == ["info", "clip"])

    # …and through the child tree's own queries
    for child <- multi.block.children, do: assert(ref_names(child) == ["info", "clip"])
  end
end
