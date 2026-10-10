defmodule Brando.Content.ModuleRerenderTest do
  @moduledoc """
  A module save syncs the blocks using it and re-renders the entries that hold
  them, from scratch (Oban runs inline here). Blocks inside a multi block are
  reached through their root.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Blocks
  alias Brando.Pages.Page
  alias Brando.Repo

  # A Text block and a Projects multi block holding three Project blocks
  # (Alpha, Beta, Gamma) on the page "Work".
  setup do
    Brando.ProposalFixtures.multi_context(Brando.ProposalFixtures.context())
  end

  defp rendered_blocks(page), do: Repo.get!(Page, page.id).rendered_blocks

  test "a change to a module nested in a multi block re-renders the entry", c do
    c.project_module
    |> Ecto.Changeset.change(code: ~s(<article class="reworked">{% ref refs.info %}</article>))
    |> Repo.update!()

    Blocks.render_entries_with_module_id(c.project_module.id)

    html = rendered_blocks(c.work)
    assert html =~ ~s(<section class="projects">)
    assert html =~ ~s(<article class="reworked">)
    for name <- ~w(Alpha Beta Gamma), do: assert(html =~ name)
    assert html =~ "Work intro"
  end

  test "syncing returns the blocks it synced", c do
    assert Enum.sort(Blocks.refresh_module_in_blocks(c.text_module.id)) ==
             Enum.sort(Blocks.list_block_ids_using_module(c.text_module.id, :local))
  end
end
