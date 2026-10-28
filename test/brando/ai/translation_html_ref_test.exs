defmodule Brando.AI.TranslationHtmlRefTest do
  # AI translation of a copied entry reads and writes only the values of an
  # HTML ref's `text` parameters, never its markup or an SVG ref's code.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.AI.Translation
  alias Brando.Content.Block
  alias Brando.Content.Ref
  alias Brando.Factory
  alias Brando.Repo
  alias Brando.Villain.Blocks.HtmlBlock
  alias Brando.Villain.Blocks.SvgBlock

  @template ~s(<div data-id="{{ checkin_id }}" title="{{ caption }}"></div>)

  setup do
    user = Factory.insert(:random_user)

    html = %HtmlBlock{
      type: "html",
      data: %HtmlBlock.Data{
        text: @template,
        params: [
          %HtmlBlock.Param{key: "checkin_id", label: "ID", type: :id},
          %HtmlBlock.Param{key: "caption", label: "Caption", type: :text}
        ],
        values: %{"checkin_id" => "abc", "caption" => "Hello"}
      }
    }

    svg = %SvgBlock{type: "svg", data: %SvgBlock.Data{code: "<svg><title>Logo</title></svg>"}}

    block =
      Repo.insert!(%Block{
        uid: Brando.Utils.generate_uid(),
        type: :module,
        creator_id: user.id,
        refs: [
          %Ref{name: "embed", uid: Brando.Utils.generate_uid(), data: html},
          %Ref{name: "logo", uid: Brando.Utils.generate_uid(), data: svg}
        ]
      })

    refs = Map.new(block.refs, &{&1.name, &1})
    %{block: block, html: refs["embed"], svg: refs["logo"]}
  end

  test "collects the values of text parameters only", %{block: block, html: html} do
    entry = %Brando.Pages.Page{entry_blocks: [%{block: %{block | vars: [], table_rows: [], children: []}}]}

    items = Translation.collect_translatable_content(entry, Brando.Pages.Page)

    assert {:ref_html_value, html.id, "caption", "Hello"} in items
    refute Enum.any?(items, &match?({:ref, _, _}, &1))
    refute Enum.any?(items, &match?({:ref_html_value, _, "checkin_id", _}, &1))
  end

  test "writes a translated value and leaves the template alone", %{html: html} do
    Translation.apply_translations([{:ref_html_value, html.id, "caption", "Hei"}], nil, Brando.Pages.Page)

    data = Repo.get!(Ref, html.id).data.data
    assert data.text == @template
    assert data.values == %{"checkin_id" => "abc", "caption" => "Hei"}
  end

  test "never writes a text item into an HTML or SVG ref", %{html: html, svg: svg} do
    Translation.apply_translations(
      [{:ref, html.id, "<i>rewritten</i>"}, {:ref, svg.id, "<svg/>"}, {:ref_html_value, html.id, "checkin_id", "x y"}],
      nil,
      Brando.Pages.Page
    )

    assert Repo.get!(Ref, html.id).data.data.text == @template
    assert Repo.get!(Ref, html.id).data.data.values["checkin_id"] == "abc"
    assert Repo.get!(Ref, svg.id).data.data.code == "<svg><title>Logo</title></svg>"
  end
end
