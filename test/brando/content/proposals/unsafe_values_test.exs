defmodule Brando.Content.Proposals.UnsafeValuesTest do
  # Values a proposal writes into ref settings, map addresses, block vars and
  # entry fields reach templates and the Villain parser as they are. The guard
  # reports markup in them as :unsafe_text, which blocks approval and the
  # preview. The parser's own escaping is tested in
  # test/brando/villain/parser/escaping_test.exs.
  use Brando.ConnCase, async: false

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.{InsertBlock, Preview, SetBlockValues, SetFields, SetRefConfig}
  alias Brando.Pages.Page

  import Brando.ProposalFixtures, only: [module!: 4, ref: 2]
  import Ecto.Query, only: [from: 2]

  # Inert payloads: each would only set document.title.
  @breakout ~s(t"><img src=x alt=MARKER onerror=document.title=this.alt><b class="x)
  @script_link "javascript:document.title='MARKER'"
  @map_breakout ~s{https://www.google.com/maps/embed?pb=1"></iframe><img src=x alt=MARKER onerror=document.title=this.alt><iframe src="https://www.google.com/maps/embed}
  @title_markup "Rooms<img src=x alt=MARKER onerror=document.title=this.alt>"
  @handler ~s(<img src=x onerror="document.title='MARKER'">)

  setup do
    Brando.ProposalFixtures.context()
  end

  defp codes(proposal), do: Enum.map(proposal.problems, & &1.code)

  defp refused_preview?(proposal, c),
    do: {:error, :unsafe_text} == Preview.render(proposal, {Page, c.identity.id}, c.user, preview_target: :blocks)

  describe "F07: header settings, map addresses and entry fields" do
    setup c do
      heading =
        module!(c.user, "Heading", "{% ref refs.heading %}",
          refs: [ref("heading", %{type: "header", data: %{text: "Rooms", level: 2}})]
        )

      where =
        module!(c.user, "Where", "{% ref refs.where %}", refs: [ref("where", %{type: "map", data: %{source: :gmaps}})])

      %{heading: heading, where: where}
    end

    test "a header's class, id or link holding markup or a script address is unsafe", c do
      for config <- [%{class: @breakout}, %{id: @breakout}, %{link: @script_link}, %{link: ~s(/rooms" onclick="x)}] do
        op = %InsertBlock{target: {Page, c.identity.id}, module: c.heading.id, configs: %{heading: config}}
        assert {:ok, proposal} = Proposals.propose([op], c.user)
        assert :unsafe_text in codes(proposal), inspect(config)
        assert {:error, _} = Proposals.approve(proposal.id, proposal.version, c.user)

        assert refused_preview?(proposal, c)
      end
    end

    test "SetRefConfig is checked the same way", c do
      op = %InsertBlock{target: {Page, c.identity.id}, module: c.heading.id}
      assert {:ok, proposal} = Proposals.propose([op], c.user)
      assert {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
      assert {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)
      [%{uid: uid}] = proposal.operations

      set = %SetRefConfig{target: {Page, c.identity.id}, block_uid: uid, ref: :heading, config: %{class: @breakout}}
      assert {:ok, proposal} = Proposals.propose([set], c.user)
      assert codes(proposal) == [:unsafe_text]
    end

    test "a link is cleared with an empty value", c do
      op = %InsertBlock{target: {Page, c.identity.id}, module: c.heading.id, configs: %{heading: %{link: ""}}}
      assert {:ok, %{problems: []}} = Proposals.propose([op], c.user)
    end

    test "a proposal stored before a check existed is checked again on approval", c do
      op = %InsertBlock{target: {Page, c.identity.id}, module: c.heading.id, configs: %{heading: %{class: @breakout}}}
      assert {:ok, proposal} = Proposals.propose([op], c.user)
      assert codes(proposal) == [:unsafe_text]

      # As a version without the check stored it.
      Brando.Repo.update_all(
        from(r in Brando.Content.Proposals.Record, where: r.id == ^proposal.id),
        set: [problems: []]
      )

      assert {:error, _} = Proposals.approve(proposal.id, proposal.version, c.user)

      # Nor previewed or shared.
      assert {:ok, stored} = Proposals.get(proposal.id, c.user)
      assert stored.problems == []
      assert {:error, :unsafe_text} = Preview.render(stored, {Page, c.identity.id}, c.user, preview_target: :blocks)
      assert {:error, :unsafe_text} = Preview.share(stored, {Page, c.identity.id}, c.user)
    end

    test "a stored approval made before a check existed cannot be applied", c do
      op = %InsertBlock{target: {Page, c.identity.id}, module: c.heading.id, configs: %{heading: %{class: @breakout}}}
      assert {:ok, proposal} = Proposals.propose([op], c.user)

      Brando.Repo.update_all(
        from(r in Brando.Content.Proposals.Record, where: r.id == ^proposal.id),
        set: [problems: [], status: "approved", approved_at: DateTime.utc_now()]
      )

      assert {:error, _} = Proposals.apply(proposal.id, proposal.version, c.user)
    end

    test "ordinary header settings stay valid", c do
      config = %{class: "title title--large", id: "rooms", link: "https://example.com/rooms?a=1&b=2"}
      op = %InsertBlock{target: {Page, c.identity.id}, module: c.heading.id, configs: %{heading: config}}
      assert {:ok, %{problems: []}} = Proposals.propose([op], c.user)
    end

    test "a map address takes an https Google Maps embed address and nothing more", c do
      for text <- [
            @map_breakout,
            "https://example.com/embed",
            "javascript:x",
            "https://www.google.com/maps/embed?pb=1&#34;"
          ] do
        op = %InsertBlock{target: {Page, c.identity.id}, module: c.where.id, texts: %{where: text}}
        assert {:ok, proposal} = Proposals.propose([op], c.user)
        assert codes(proposal) == [:unsafe_text], text

        assert refused_preview?(proposal, c)
      end

      ok = %InsertBlock{
        target: {Page, c.identity.id},
        module: c.where.id,
        texts: %{where: "https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d1999.4&hl=no"}
      }

      assert {:ok, %{problems: []}} = Proposals.propose([ok], c.user)

      no = %InsertBlock{
        target: {Page, c.identity.id},
        module: c.where.id,
        texts: %{where: "https://maps.google.no/maps?q=Oslo&output=embed"}
      }

      assert {:ok, %{problems: []}} = Proposals.propose([no], c.user)
    end

    test "an entry's text fields take no unsafe markup", c do
      op = %SetFields{target: {Page, c.identity.id}, fields: %{title: @title_markup}}
      assert {:ok, proposal} = Proposals.propose([op], c.user)
      assert codes(proposal) == [:unsafe_text]
      assert {:error, _} = Proposals.approve(proposal.id, proposal.version, c.user)

      nested = %SetFields{target: {Page, c.identity.id}, fields: %{meta_description: %{"en" => [@title_markup]}}}
      assert {:ok, proposal} = Proposals.propose([nested], c.user)
      assert :unsafe_text in codes(proposal)

      ok = %SetFields{
        target: {Page, c.identity.id},
        fields: %{title: ~s(Rooms & "suites" > 100 kr — it's <b>open</b>), meta_description: "> A quote"}
      }

      assert {:ok, %{problems: []}} = Proposals.propose([ok], c.user)
    end
  end

  describe "F08: block var values" do
    setup c do
      module =
        module!(c.user, "Note", ~s(<h2>{{ heading }}</h2><div>{{ note }}</div><p>{{ summary }}</p>{% link cta %}),
          vars: [
            %{type: "string", key: "heading", label: "Heading", value: "Heading"},
            %{type: "html", key: "note", label: "Note", value: "<p>Note</p>"},
            %{type: "text", key: "summary", label: "Summary", value: "Summary"},
            %{type: "link", key: "cta", label: "Read more", value: "https://example.com"}
          ]
        )

      %{note: module}
    end

    test "a string var takes plain text, a text or html var safe rich text, a link var an address", c do
      for values <- [
            %{heading: "Hi " <> @handler},
            %{note: @handler},
            %{summary: @handler},
            %{cta: @script_link},
            %{cta: "  javascript:x"},
            %{cta: "data:text/html,x"},
            %{cta: ~s(/about" onmouseover="x)},
            %{cta: "javascript&#58;x"}
          ] do
        op = %InsertBlock{target: {Page, c.identity.id}, module: c.note.id, values: values}
        assert {:ok, proposal} = Proposals.propose([op], c.user)
        assert codes(proposal) == [:unsafe_text], inspect(values)
        assert {:error, _} = Proposals.approve(proposal.id, proposal.version, c.user)
      end
    end

    test "SetBlockValues and table rows go through the same check", c do
      op = %InsertBlock{target: {Page, c.identity.id}, module: c.note.id}
      assert {:ok, proposal} = Proposals.propose([op], c.user)
      assert {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
      assert {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)
      [%{uid: uid}] = proposal.operations

      set = %SetBlockValues{target: {Page, c.identity.id}, block_uid: uid, values: %{note: @handler}}
      assert {:ok, proposal} = Proposals.propose([set], c.user)
      assert codes(proposal) == [:unsafe_text]
    end

    test "the link tag escapes the address and leaves out script addresses", c do
      op = %InsertBlock{target: {Page, c.identity.id}, module: c.note.id, values: %{cta: @script_link}}
      assert {:ok, proposal} = Proposals.propose([op], c.user)
      assert refused_preview?(proposal, c)

      render = fn url ->
        var = %Brando.Content.Var{type: :link, key: "cta", link_type: :url, value: url, link_text: "Go"}
        Brando.Villain.parse_and_render("{% link cta %}", Liquex.Context.new(%{"cta" => var}))
      end

      assert render.(@script_link) =~ ~s(href="")
      assert render.(~s(/a" onclick="x)) =~ ~s(href="/a&quot; onclick=&quot;x")
      assert render.("tel:+47 22 33 44 55") =~ ~s(href="tel:+47 22 33 44 55")
      assert render.("https://example.com/?a=1&amp;b=2") =~ ~s(href="https://example.com/?a=1&amp;b=2")
    end

    test "ordinary values stay valid", c do
      values = %{
        heading: ~s(Rooms & "suites" — it's open),
        note: ~s(<p>A <a href="https://example.com">link</a> &amp; <strong>text</strong></p>),
        summary: "Two lines\nof text",
        cta: "mailto:post@example.com"
      }

      op = %InsertBlock{target: {Page, c.identity.id}, module: c.note.id, values: values}
      assert {:ok, %{problems: []}} = Proposals.propose([op], c.user)

      for cta <- ["/about", "https://example.com/a?b=1&c=2", "tel:+47 22 33 44 55", "#top", "/o'brien"] do
        op = %InsertBlock{target: {Page, c.identity.id}, module: c.note.id, values: %{cta: cta}}
        assert {:ok, %{problems: []}} = Proposals.propose([op], c.user), cta
      end
    end

    test "a value cannot carry Liquid, which the page would render", c do
      liquid = ~s({{ "%3Cimg src=x onerror=x%3E" | url_decode }})

      for values <- [%{heading: liquid}, %{note: "<p>#{liquid}</p>"}, %{cta: "/a?{% raw %}"}] do
        op = %InsertBlock{target: {Page, c.identity.id}, module: c.note.id, values: values}
        assert {:ok, proposal} = Proposals.propose([op], c.user)
        assert codes(proposal) == [:unsafe_text], inspect(values)
      end

      op = %SetFields{target: {Page, c.identity.id}, fields: %{title: liquid}}
      assert {:ok, proposal} = Proposals.propose([op], c.user)
      assert codes(proposal) == [:unsafe_text]

      # Spelled with character references, which an attribute is rendered with decoded.
      encoded = "&#123;&#123; x | url_decode &#125;&#125;"
      op = %InsertBlock{target: {Page, c.identity.id}, module: c.note.id, values: %{heading: encoded}}
      assert {:ok, proposal} = Proposals.propose([op], c.user)
      assert codes(proposal) == [:unsafe_text]
    end

    test "an unresolved entry link no longer hides the rest of a rich text", c do
      text = ~s(<p><a href="entry:Brando.Pages.Page:999999">x</a></p>) <> @handler
      op = %InsertBlock{target: {Page, c.identity.id}, module: c.text_module.id, texts: %{body: text}}
      assert {:ok, proposal} = Proposals.propose([op], c.user)
      assert :unsafe_text in codes(proposal)
      assert :unknown_target in codes(proposal)

      hidden = ~s(<p><a href="entry:<img src=x onerror=x>">x</a></p>)
      op = %InsertBlock{target: {Page, c.identity.id}, module: c.text_module.id, texts: %{body: hidden}}
      assert {:ok, proposal} = Proposals.propose([op], c.user)
      assert :unsafe_text in codes(proposal)

      clean = %InsertBlock{
        target: {Page, c.identity.id},
        module: c.text_module.id,
        texts: %{body: ~s(<p><a href="entry:Brando.Pages.Page:999999">x</a></p>)}
      }

      assert {:ok, proposal} = Proposals.propose([clean], c.user)
      assert codes(proposal) == [:unknown_target]
    end
  end
end
