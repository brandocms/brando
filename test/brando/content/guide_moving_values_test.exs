defmodule Brando.Content.GuideMovingValuesTest do
  # Runs the example in guides/module_definitions.md, "Moving values to
  # child modules", as the guide prints it, so the guide cannot drift from
  # the functions it calls.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{Block, Var}
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures
  alias Brando.Repo

  @guide "guides/module_definitions.md"

  setup_all do
    [_, section] = String.split(File.read!(@guide), "### Moving values to child modules\n", parts: 2)
    [_, code | _] = String.split(section, ~r/^```(elixir)?\n/m, parts: 3)
    [code | _] = String.split(code, ~r/^```\n/m, parts: 2)
    [{module, _}] = Code.compile_string(code, @guide)
    %{migration: module}
  end

  # A "media-row" module whose blocks hold `layout`, and a child "media"
  # module whose blocks get the new `width` var, both of `type`; a page
  # with one row holding `layout` and two items
  defp row_page!(user, type, layout) do
    item = ProposalFixtures.module!(user, "Media", "<figure>{{ width }}</figure>", vars: [var(type, "width")])

    row =
      ProposalFixtures.module!(user, "Media row", "<div>{{ content }}</div>", multi: true, vars: [var(type, "layout")])

    Repo.update_all(from(m in Brando.Content.Module, where: m.id == ^row.id), set: [uid: "media-row"])
    Repo.update_all(from(m in Brando.Content.Module, where: m.id == ^item.id), set: [parent_id: row.id])

    page = Brando.Factory.insert(:page, creator: user, title: "Media", uri: "media")
    parent = insert_block!(user, row, :module, nil)
    struct(Page.Blocks, %{entry_id: page.id, block_id: parent.id, sequence: 0}) |> Repo.insert!()
    insert_var!(parent, type, "layout", layout)

    items =
      for n <- 0..1 do
        child = insert_block!(user, item, :module_entry, parent.id, n)
        insert_var!(child, type, "width", nil)
        child
      end

    {page, items}
  end

  defp var(type, key), do: %{type: to_string(type), key: key, label: key}

  defp insert_block!(user, module, type, parent_id, sequence \\ 0) do
    Repo.insert!(%Block{
      uid: Brando.Utils.generate_uid(),
      type: type,
      module_id: module.id,
      multi: type == :module,
      parent_id: parent_id,
      sequence: sequence,
      creator_id: user.id,
      source: Page.Blocks
    })
  end

  defp insert_var!(block, :boolean, key, value),
    do: Repo.insert!(%Var{block_id: block.id, key: key, type: :boolean, label: %{"en" => key}, value_boolean: value})

  defp insert_var!(block, type, key, value),
    do: Repo.insert!(%Var{block_id: block.id, key: key, type: type, label: %{"en" => key}, value: value})

  defp width(block), do: Repo.get_by!(Var, block_id: block.id, key: "width")

  defp revisions(page),
    do: Repo.aggregate(from(r in Brando.Revisions.Revision, where: r.entry_id == ^page.id), :count)

  test "moves a string value onto each item, with revisions before and after, and renders the page", c do
    user = Brando.Factory.insert(:random_user)
    {page, items} = row_page!(user, :string, "wide")

    c.migration.run(user)

    assert Enum.map(items, &width(&1).value) == ["wide", "wide"]
    assert revisions(page) == 2
    assert Repo.get!(Page, page.id).rendered_blocks =~ "<figure>wide</figure>"
  end

  test "moves a boolean value, which a var holds in its own column", c do
    user = Brando.Factory.insert(:random_user)
    {_page, items} = row_page!(user, :boolean, true)

    c.migration.run(user)

    assert Enum.map(items, &width(&1).value_boolean) == [true, true]
  end
end
