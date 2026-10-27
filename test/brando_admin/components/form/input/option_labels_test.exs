defmodule BrandoAdmin.Components.Form.Input.OptionLabelsTest do
  # Option labels are text. Entry titles, user names and module params are
  # data other admins control, so a select, multi-select or radio shows a
  # label's markup as written. Code that wants markup in a label (a palette's
  # swatches) passes it as `{:safe, iodata}`. Each payload is an image with an
  # inert marker attribute; a live one in the render would be markup that runs.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 2]

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.MultiSelect
  alias BrandoAdmin.Components.Form.Input.Options
  alias BrandoAdmin.Components.Form.Input.Select
  alias Ecto.Changeset
  alias Phoenix.LiveViewTest

  require Phoenix.LiveViewTest

  @label ~s(Large<img src="x" data-marker="label"> & co)

  defp title_field(value \\ "one") do
    to_form(Changeset.change(%Brando.Pages.Page{title: value}), as: "entry")[:title]
  end

  defp markers(doc), do: doc |> LazyHTML.query("[data-marker]") |> LazyHTML.attribute("data-marker")
  defp text_of(doc, selector), do: doc |> LazyHTML.query(selector) |> LazyHTML.text()
  defp attr_of(doc, selector, attr), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(attr)

  defp render_select(options, extra \\ []) do
    Select
    |> LiveViewTest.render_component(id: "select", field: title_field(), opts: [options: options] ++ extra, open: true)
    |> LazyHTML.from_fragment()
  end

  describe "Options" do
    test "a label is escaped text unless code passes it as {:safe, iodata}" do
      assert Options.label_html(@label) == ~s(Large&lt;img src=&quot;x&quot; data-marker=&quot;label&quot;&gt; &amp; co)
      assert Options.label_html({:safe, ["<em>", "Big", "</em>"]}) == "<em>Big</em>"
      assert Options.label_html(nil) == ""

      assert Options.label_text(@label) == @label
      assert Options.label_text({:safe, ~s(<span class="circle"></span><em>Big</em>)}) == "Big"
      # the text a filter matches, so entities are decoded
      assert Options.label_text({:safe, ~s(<span class="text-mono">Black &amp; White &lt;3</span>)}) ==
               "Black & White <3"
    end
  end

  describe "Select" do
    test "a label's markup shows as text in the options, the selected label and the optimistic label" do
      doc = render_select([%{label: @label, value: "one"}])

      assert markers(doc) == []
      assert text_of(doc, ".options-option") =~ @label
      assert text_of(doc, ".select-label") =~ @label
      assert attr_of(doc, ".options-option", "data-label") == [@label]
      # set as innerHTML by `b:select-option`, so it holds the escaped label
      assert attr_of(doc, ".options-option", "data-select-label") == [Options.label_html(@label)]
    end

    test "inline options escape the label too" do
      doc =
        Select
        |> LiveViewTest.render_component(
          id: "select",
          field: title_field(),
          opts: [options: [%{label: @label, value: "one"}], inline: true],
          open: true
        )
        |> LazyHTML.from_fragment()

      assert markers(doc) == []
      assert text_of(doc, ".inline-options .options-option") =~ @label
    end

    test "an options function's labels are escaped" do
      doc = render_select(fn _form, _opts -> [%{label: @label, value: "one"}] end)

      assert markers(doc) == []
      assert text_of(doc, ".options-option") =~ @label
    end

    test "a custom value shows as text" do
      doc =
        Select
        |> LiveViewTest.render_component(
          id: "select",
          field: title_field(@label),
          opts: [options: [], allow_custom: true]
        )
        |> LazyHTML.from_fragment()

      assert markers(doc) == []
      assert text_of(doc, ".select-label") =~ @label
    end

    test "a {:safe, iodata} label from code is markup, and its text is what the filter matches" do
      label = {:safe, ~s(<span class="swatch" data-marker="safe"></span><em>Big</em>)}
      doc = render_select([%{label: label, value: "one"}])

      assert markers(doc) == ["safe", "safe"]
      assert doc |> LazyHTML.query(".options-option em") |> LazyHTML.text() == "Big"
      assert attr_of(doc, ".options-option", "data-label") == ["Big"]
      assert attr_of(doc, ".options-option", "data-select-label") == [Phoenix.HTML.safe_to_string(label)]
    end
  end

  describe "MultiSelect" do
    test "a label's markup shows as text in the options and the selection" do
      var = %Brando.Content.Var{type: :link, key: "link", link_identifier_schemas: ["one"]}
      field = to_form(Changeset.change(var), as: "var")[:link_identifier_schemas]

      doc =
        MultiSelect
        |> LiveViewTest.render_component(
          id: "multi",
          field: field,
          opts: [options: [%{label: @label, value: "one"}]],
          open: true
        )
        |> LazyHTML.from_fragment()

      assert markers(doc) == []
      assert text_of(doc, ".multiselect-option") =~ @label
      assert @label in attr_of(doc, "[data-label]", "data-label")
    end
  end

  describe "radios" do
    test "an options function's labels are escaped; a {:safe, iodata} label is kept" do
      options = fn _form, _opts ->
        [%{label: @label, value: "one"}, %{label: {:safe, ~s(<em data-marker="safe">Big</em>)}, value: "two"}]
      end

      doc =
        (&Input.radios/1)
        |> LiveViewTest.render_component(field: title_field(), opts: [options: options], label: "Size", id: nil)
        |> LazyHTML.from_fragment()

      assert markers(doc) == ["safe"]
      assert text_of(doc, ".label-text") =~ @label
    end
  end

  describe "container palettes" do
    test "a palette's name and colours are escaped in its swatch label" do
      user = Brando.Factory.insert(:random_user)

      Brando.Factory.insert(:palette,
        name: @label,
        key: "marked",
        namespace: ~s(ns<img src="x" data-marker="namespace">),
        status: :published,
        creator: user,
        colors: [
          Brando.Factory.build(:color, hex_value: "#00ff00"),
          Brando.Factory.build(:color, hex_value: ~s(#f00"><img src="x" data-marker="color">))
        ]
      )

      [%{label: {:safe, _} = label}] =
        Enum.filter(Brando.Content.Container.get_palettes(nil, nil), &(elem(&1.label, 1) =~ "Large"))

      doc = label |> Phoenix.HTML.safe_to_string() |> LazyHTML.from_fragment()

      assert markers(doc) == []
      assert text_of(doc, ".text-mono") =~ @label
      # A stored non-colour gets no swatch (`Palette.css_colors/1`)
      assert doc |> LazyHTML.query(".circle") |> Enum.count() == 1
    end
  end
end
