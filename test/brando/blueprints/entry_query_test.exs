defmodule Brando.Blueprint.EntryQueryTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Blueprint.EntryQuery
  alias Brando.EntryQueryTestContext.ActiveEntry
  alias Brando.Factory
  alias Brando.Pages.Page

  test "loads complete soft-deleted entries through their generated context query" do
    page = Factory.insert(:page)
    assert {:ok, deleted_page} = Brando.Repo.soft_delete(page)
    assert {:ok, loaded_page} = EntryQuery.get(Page, page.id)

    assert loaded_page.id == deleted_page.id
    assert loaded_page.deleted_at == deleted_page.deleted_at
    assert Ecto.assoc_loaded?(loaded_page.entry_blocks)
  end

  test "does not send soft-delete options to schemas without the trait" do
    assert EntryQuery.get(ActiveEntry, "entry-id") == {:ok, :active_entry}

    assert_received {:active_entry_options,
                     %{
                       matches: %{id: "entry-id"},
                       preload: [:owner]
                     }}
  end

  test "the public query facade retains complete Blueprint entry loading" do
    page = Factory.insert(:page)
    assert {:ok, deleted_page} = Brando.Repo.soft_delete(page)
    assert {:ok, loaded_page} = Brando.Query.get_entry(Page, page.id)

    assert loaded_page.id == deleted_page.id
    assert loaded_page.deleted_at == deleted_page.deleted_at
    assert Ecto.assoc_loaded?(loaded_page.entry_blocks)
  end
end
