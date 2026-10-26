defmodule BrandoAdmin.Live.BlockEditorEscapeTest do
  # What an editor writes into a page is data in another admin's block
  # editor: the entry title a module prints, a comment ref, an SVG ref's code
  # and a select var's option labels all arrive as text, never as markup.
  # Each payload is an image element with an inert marker attribute; a live
  # one in the superuser's render means the editor's markup would run there.
  use Brando.LiveCase

  alias Brando.Content.Block
  alias Brando.Content.Ref
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Villain.Blocks.CommentBlock
  alias Brando.Villain.Blocks.SvgBlock

  @title ~s(Rooms<img src="x" data-f04="title">)
  @comment ~s(Note<img src="x" data-f04="comment">)
  @svg ~s(<svg xmlns="http://www.w3.org/2000/svg"><image href="x" data-f04="svg"/></svg>)
  @option ~s(Large<img src="x" data-f04="option">)
  @form_title ~s(Contact<img src="x" data-f04="form">)

  setup %{current_user: superuser} do
    editor = Factory.insert(:random_user, role: :editor)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{
          code: """
          <h2>{{ entry.title }}</h2>
          {% ref refs.note %}
          {% ref refs.logo %}
          {{ size }}
          {{ contact }}
          """,
          refs: [
            ref_params("note", %{type: "comment", data: %{text: "x"}}),
            ref_params("logo", %{type: "svg", data: %{code: nil}})
          ],
          vars: [
            %{key: "size", label: "Size", type: :select, placement: :content},
            %{key: "contact", label: "Contact form", type: :form, placement: :content}
          ]
        }),
        superuser
      )

    {:ok, form} =
      Brando.Forms.create_form(
        %{
          "title" => @form_title,
          "key" => "f04-contact",
          "language" => "en",
          "status" => "published",
          "fields" => [%{"key" => "name", "type" => "text", "label" => "Name"}]
        },
        editor
      )

    block = %Block{
      type: :module,
      active: true,
      source: Brando.Pages.Page.Blocks,
      module_id: module.id,
      uid: Brando.Utils.generate_uid(),
      creator_id: editor.id,
      refs: [
        %Ref{
          name: "note",
          uid: Brando.Utils.generate_uid(),
          data: %CommentBlock{data: %CommentBlock.Data{text: @comment}}
        },
        %Ref{
          name: "logo",
          uid: Brando.Utils.generate_uid(),
          data: %SvgBlock{data: %SvgBlock.Data{code: @svg}}
        }
      ],
      vars: [
        %Var{
          key: "size",
          label: %{"en" => "Size"},
          type: :select,
          placement: :content,
          value: "l",
          options: [%Var.Option{label: %{"en" => @option}, value: "l"}],
          creator_id: editor.id
        },
        %Var{
          key: "contact",
          label: %{"en" => "Contact form"},
          type: :form,
          placement: :content,
          form_id: form.id,
          creator_id: editor.id,
          sequence: 1
        }
      ]
    }

    page =
      Factory.insert(:page,
        title: "Rooms",
        creator: editor,
        entry_blocks: [%Brando.Pages.Page.Blocks{sequence: 0, block: block}]
      )

    {:ok, page} = Brando.Pages.update_page(page, %{"title" => @title}, editor)
    {:ok, page: page}
  end

  test "the page editor shows an editor's markup as text", %{conn: conn, page: page} do
    {:ok, view, _html} = live(conn, "/admin/pages/update/#{page.id}")
    render_async(view)
    doc = view |> render() |> LazyHTML.from_fragment()

    assert live_markers(doc) == []

    assert text_of(doc, ".rendered-variable") =~ @title
    assert text_of(doc, "[id$='-comment']") =~ @comment
    assert text_of(doc, ".select-label") =~ @option
    assert text_of(doc, ".select-label") =~ @form_title

    [src] = doc |> LazyHTML.query(".svg-block-preview img") |> LazyHTML.attribute("src")
    assert src == "data:image/svg+xml;base64," <> :base64.encode(@svg)
  end

  defp ref_params(name, data) do
    %{name: name, description: nil, uid: Brando.Utils.generate_uid(), data: data}
  end

  defp live_markers(doc) do
    doc |> LazyHTML.query("[data-f04]") |> LazyHTML.attribute("data-f04")
  end

  defp text_of(doc, selector) do
    doc |> LazyHTML.query(selector) |> LazyHTML.text()
  end
end
