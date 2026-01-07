defmodule Brando.Content.Identifier.QueriesTest do
  use ExUnit.Case

  alias Brando.Content.Identifier.Queries
  alias Brando.Pages.Page

  describe "list_entry_types/0" do
    test "returns list of entry types" do
      {:ok, entry_types} = Queries.list_entry_types()
      assert is_list(entry_types)

      # Should include Page
      assert Enum.any?(entry_types, fn {_plural, module} -> module == Page end)
    end
  end

  describe "get_entry_types/1" do
    test "transforms wanted types to entry type tuples" do
      wanted = [{Page, %{limit: 10}}]
      result = Queries.get_entry_types(wanted)

      assert length(result) == 1
      {plural, module, opts} = List.first(result)
      assert is_binary(plural)
      assert module == Page
      assert opts == %{limit: 10}
    end

    test "handles multiple wanted types" do
      wanted = [{Page, %{limit: 10}}, {Brando.Pages.Fragment, %{limit: 5}}]
      result = Queries.get_entry_types(wanted)

      assert length(result) == 2
    end
  end

  describe "identifier_for/1" do
    test "returns nil for entry without __identifier__ function" do
      entry = %{__struct__: Brando.Content.Block, id: 1}
      assert Queries.identifier_for(entry) == nil
    end

    test "generates identifier for Page entry" do
      entry = %Page{
        id: 1,
        title: "Test Page",
        status: :published,
        language: :en,
        uri: "test-page"
      }

      result = Queries.identifier_for(entry)

      assert result != nil
      assert result.entry_id == 1
      assert result.title == "Test Page"
    end
  end

  describe "identifiers_for/1" do
    test "returns identifiers for list of entries" do
      entries = [
        %Page{id: 1, title: "Page 1", status: :published, language: :en, uri: "page-1"},
        %Page{id: 2, title: "Page 2", status: :draft, language: :en, uri: "page-2"}
      ]

      {:ok, identifiers} = Queries.identifiers_for(entries)

      assert length(identifiers) == 2
      assert Enum.at(identifiers, 0).title == "Page 1"
      assert Enum.at(identifiers, 1).title == "Page 2"
    end
  end

  describe "identifiers_for!/1" do
    test "returns unwrapped identifiers for list of entries" do
      entries = [
        %Page{id: 1, title: "Page 1", status: :published, language: :en, uri: "page-1"}
      ]

      identifiers = Queries.identifiers_for!(entries)

      assert length(identifiers) == 1
      assert List.first(identifiers).title == "Page 1"
    end
  end
end
