defmodule Brando.AI.ContextTest do
  use ExUnit.Case, async: true

  alias Brando.AI.Context
  alias Brando.Pages.Page

  describe "for_entry/3" do
    test "reads attributes in the order asked for, formatted as plain text" do
      entry = %Page{title: "Om oss", meta_description: "<p>Kort og godt</p>"}

      assert Context.for_entry(entry, [:meta_description, :title]) == [
               {:meta_description, "Kort og godt"},
               {:title, "Om oss"}
             ]
    end

    test "leaves out fields that are empty or missing" do
      entry = %Page{title: "Om oss", meta_description: nil}

      assert Context.for_entry(entry, [:title, :meta_description, :nope]) == [{:title, "Om oss"}]
    end

    test "reads block fields from the rendered column rather than the block tree" do
      entry = %Page{title: "Om oss", rendered_blocks: "<h2>Tittel</h2><p>Brød &amp; tekst</p>"}

      assert Context.for_entry(entry, [:blocks]) == [{:blocks, "Tittel Brød & tekst"}]
      assert Context.for_entry(entry, [:blocks], length: 6) == [{:blocks, "Tit..."}]
    end

    test "accepts strings, and drops ones that name nothing" do
      entry = %Page{title: "Om oss"}

      assert Context.for_entry(entry, ["title", "no_such_field_anywhere"]) == [{:title, "Om oss"}]
    end

    test "an entry without blocks contributes nothing for :blocks" do
      assert Context.for_entry(%Page{title: "Om oss"}, [:blocks]) == []
      assert Context.for_entry(nil, [:title]) == []
    end
  end

  describe "available_fields/1" do
    test "offers the schema's own text and block fields, not its meta fields" do
      fields = Context.available_fields(Page)

      assert :title in fields
      assert :blocks in fields
      refute :meta_title in fields
      refute :meta_description in fields
      refute :uri in fields
    end
  end

  describe "build_prompt/2" do
    test "appends the context it was given" do
      prompt = Context.build_prompt("Write a description.", title: "Om oss", blocks: "Tekst")

      assert prompt == "Write a description.\n\nContext:\ntitle: Om oss\nblocks: Tekst"
    end

    test "leaves a prompt without context alone" do
      assert Context.build_prompt("Write a description.", []) == "Write a description."
    end
  end

  describe "normalize_fields/1" do
    test "wraps, converts and rejects" do
      assert Context.normalize_fields(:title) == [:title]
      assert Context.normalize_fields(["title", :blocks, 1, "not_an_atom_anywhere"]) == [:title, :blocks]
      assert Context.normalize_fields(nil) == []
    end
  end
end
