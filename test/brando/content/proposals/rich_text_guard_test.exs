defmodule Brando.Content.Proposals.RichTextGuardTest do
  # The proposal guard reports rich text a browser would build a handler or
  # script address from, however another parser reads it. The handlers
  # would only set document.title.
  use Brando.ConnCase, async: false

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.InsertBlock
  alias Brando.Pages.Page

  import Brando.ProposalFixtures, only: [module!: 4, ref: 2]

  @handler "<img src=x alt=MARKER onerror=document.title=this.alt>"

  setup do
    c = Brando.ProposalFixtures.context()

    module =
      module!(c.user, "Mixed", "{% ref refs.body %}{% ref refs.notes %}{% ref refs.icon %}",
        refs: [
          ref("body", %{type: "text", data: %{text: "<p>Body</p>"}}),
          ref("notes", %{type: "markdown", data: %{text: "Notes"}}),
          ref("icon", %{type: "svg", data: %{code: "<svg></svg>"}})
        ]
      )

    Map.put(c, :mixed, module)
  end

  defp codes(c, texts) do
    op = %InsertBlock{target: {Page, c.identity.id}, module: c.mixed.id, texts: texts}
    {:ok, proposal} = Proposals.propose([op], c.user)
    Enum.map(proposal.problems, & &1.code)
  end

  test "rich text that hides a handler from another parser is unsafe", c do
    for body <- [
          "<p>Hi</p><!-->#{@handler}-->",
          ~s(<p>Hi</p><xmp><p title="</xmp>#{@handler}"></p></xmp>),
          "<p>Hi</p><![CDATA[>#{@handler}]]>",
          ~s(<p>Hi</p><noscript><p title="</noscript>#{@handler}"></p></noscript>),
          ~s(<p>Hi</p><noembed><p title="</noembed>#{@handler}"></p></noembed>),
          ~s(<p>Hi</p><noframes><p title="</noframes>#{@handler}"></p></noframes>)
        ] do
      assert codes(c, %{body: body}) == [:unsafe_text], body
    end
  end

  # SVG code is markup only a superuser changes, safe or not
  test "an svg takes no text from a proposal", c do
    assert codes(c, %{icon: ~s(<svg viewBox="0 0 10 10"><!-->#{@handler}--></svg>)}) == [:unsupported_value]
    assert codes(c, %{icon: ~s(<svg viewBox="0 0 10 10"><title>Dot</title></svg>)}) == [:unsupported_value]
  end

  test "Markdown is checked as the HTML it renders", c do
    assert codes(c, %{notes: "[Read more](javascript:document.title='MARKER')"}) == [:unsafe_text]
    assert codes(c, %{notes: ~s(Hi\n\n<img src="x" onerror="document.title='MARKER'">)}) == [:unsafe_text]
    assert codes(c, %{notes: "Some *notes* and [a link](https://example.com)"}) == []

    # An entry link in it skips nothing.
    assert :unsafe_text in codes(c, %{notes: ~s{[x](entry:Brando.Pages.Page:1)\n\n<img src="x" onerror="x">}})
  end

  test "ordinary rich text stays valid", c do
    body =
      ~s(<p class="lede">A <a href="https://example.com/?a=1&amp;b=2" target="_blank">link</a> &amp; <strong>text</strong></p>)

    assert codes(c, %{body: body}) == []
  end
end
