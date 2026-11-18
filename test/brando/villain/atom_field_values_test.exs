defmodule Brando.Villain.AtomFieldValuesTest do
  # An entry's status and language are atoms, and Liquid has no atoms: a
  # template compares them with text, `{% if e.status == "draft" %}`. A
  # template reads them as text, so the comparison holds and printing them
  # gives what it always did. Tags get the value itself.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Villain
  alias Brando.Villain.TemplateView

  defmodule AtomFilters do
    @moduledoc false
    use Brando.Villain.Filters

    def kind(_value, _context), do: :lede
    def kinds(_value, _context), do: [:lede, :lead]
  end

  @compare ~S"""
  [status={{ X.status }}]{% if X.status == "draft" %}[is-draft]{% endif %}{% if X.status == "published" %}[is-published]{% endif %}{% if X.status != "draft" %}[not-draft]{% endif %}{% case X.status %}{% when "draft" %}[case-draft]{% when "published" %}[case-published]{% endcase %}[language={{ X.language }}]{% if X.language == "en" %}[is-en]{% endif %}
  """

  @get_entry "{% assign e = card.identifier | get_entry %}{% if e %}" <>
               String.replace(@compare, "X.", "e.") <> "{% else %}[no-card]{% endif %}"

  @own_entry String.replace(@compare, "X.", "entry.")

  setup do
    user = Factory.insert(:random_user)
    {:ok, user: user}
  end

  defp create_module(user, code) do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{
          code: code,
          vars: [%{type: :link, key: "card", label: "Card", link_type: :identifier, creator_id: user.id}]
        }),
        :system
      )

    module
  end

  defp create_page(user, attrs) do
    params =
      Map.merge(
        %{title: "Launch", uri: "launch-#{System.unique_integer([:positive])}", language: "en", template: "default.html"},
        attrs
      )

    {:ok, page} = Oban.Testing.with_testing_mode(:manual, fn -> Pages.create_page(params, user) end)
    page
  end

  # A page with one module block, its link var pointing at `target`
  defp create_page_with_block(user, module, attrs, target \\ nil) do
    page = create_page(user, attrs)
    target = target || page
    {:ok, identifier} = Brando.Content.get_identifier(Page, target)

    block =
      Brando.Repo.insert!(%Brando.Content.Block{
        type: :module,
        source: "Elixir.Brando.Pages.Page.Blocks",
        module_id: module.id,
        uid: Brando.Utils.generate_uid(),
        creator_id: user.id,
        vars: [
          %Brando.Content.Var{
            type: :link,
            key: "card",
            label: "Card",
            link_type: :identifier,
            identifier_id: identifier.id,
            creator_id: user.id
          }
        ]
      })

    Brando.Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
    {:ok, _} = Brando.Content.Blocks.render_entry(Page, page.id)
    page
  end

  defp stored(page), do: Brando.Repo.get(Page, page.id).rendered_blocks

  defp live_preview(page) do
    {:ok, entry} = Brando.Query.get_entry(Page, page.id)
    cache_key = "atom-fields-#{System.unique_integer([:positive])}"
    on_exit(fn -> Brando.LivePreview.cleanup_cache(cache_key) end)
    Brando.LivePreview.render(Page, entry, cache_key, target: :blocks)
  end

  defp block_patch(page) do
    {:ok, entry} = Brando.Query.get_entry(Page, page.id)
    [%{block: block}] = entry.entry_blocks
    Villain.render_block(block, entry, annotate_blocks: true)
  end

  defp assert_draft(html) do
    assert html =~ "[status=draft][is-draft][case-draft][language=en][is-en]"
    refute html =~ "[is-published]"
    refute html =~ "[not-draft]"
  end

  defp assert_published(html) do
    assert html =~ "[status=published][is-published][not-draft][case-published][language=en][is-en]"
    refute html =~ "[is-draft]"
  end

  describe "an entry loaded with get_entry" do
    test "compares its status and language with text in the stored render", c do
      module = create_module(c.user, @get_entry)
      target = create_page(c.user, %{status: :published})
      page = create_page_with_block(c.user, module, %{status: :published}, target)

      assert_published(stored(page))
    end

    test "compares its status and language with text in live preview and a block patch", c do
      module = create_module(c.user, @get_entry)
      target = create_page(c.user, %{status: :draft})
      page = create_page_with_block(c.user, module, %{status: :published}, target)

      # The stored render shows no draft
      assert stored(page) =~ "[no-card]"
      assert_draft(live_preview(page))
      assert_draft(block_patch(page))
    end
  end

  describe "the page's own entry" do
    test "compares its status and language with text in the stored render", c do
      module = create_module(c.user, @own_entry)

      assert_draft(stored(create_page_with_block(c.user, module, %{status: :draft})))
      assert_published(stored(create_page_with_block(c.user, module, %{status: :published})))
    end

    test "compares its status and language with text in live preview and a block patch", c do
      module = create_module(c.user, @own_entry)

      draft = create_page_with_block(c.user, module, %{status: :draft})
      assert_draft(live_preview(draft))
      assert_draft(block_patch(draft))

      published = create_page_with_block(c.user, module, %{status: :published})
      assert_published(live_preview(published))
      assert_published(block_patch(published))
    end

    test "compares its status with text in a Markdown template", c do
      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module, %{code: "<p>x</p>", markdown_code: String.replace(@compare, "X.", "entry.")}),
          :system
        )

      page = create_page_with_block(c.user, module, %{status: :draft})
      {:ok, entry} = Brando.Query.get_entry(Page, page.id)

      assert_draft(Villain.Markdown.render(entry.entry_blocks, entry))
    end
  end

  describe "a template view" do
    defp eval(value, path) do
      context = Villain.create_context(%{"x" => TemplateView.wrap(value)})
      {result, _} = Liquex.Argument.eval({:field, Enum.map(["x" | path], &{:key, &1})}, context)
      result
    end

    test "reads an atom field, and the atoms in a list field, as text" do
      assert eval(%{status: :draft}, ["status"]) == "draft"
      assert eval(%{formats: [:jpg, :webp]}, ["formats"]) == ["jpg", "webp"]
      assert eval(%{nested: %{kind: :lede}}, ["nested", "kind"]) == "lede"
    end

    test "keeps nil, true and false" do
      assert eval(%{a: nil, b: true, c: false}, ["a"]) == nil
      assert eval(%{a: nil, b: true, c: false}, ["b"]) == true
      assert eval(%{a: nil, b: true, c: false}, ["c"]) == false
      assert eval(%{list: [true, nil, :x]}, ["list"]) == [true, nil, "x"]
    end

    test "a list of atoms contains its text" do
      context = Villain.create_context(%{"image" => TemplateView.wrap(%{formats: [:jpg, :webp]})})
      {:ok, template} = Liquex.parse(~S({% if image.formats contains "webp" %}yes{% endif %}{{ image.formats }}))

      assert template |> Liquex.render!(context) |> elem(0) |> IO.iodata_to_binary() == "yesjpgwebp"
    end

    test "the where filter matches an atom field with its text" do
      entries = TemplateView.wrap([%{title: "A", status: :draft}, %{title: "B", status: :published}])
      context = Villain.create_context(%{"entries" => entries})

      {:ok, template} =
        Liquex.parse(
          ~S({% assign drafts = entries | where: "status", "draft" %}{% for e in drafts %}{{ e.title }}{% endfor %}|{{ entries | map: "status" | join: "," }})
        )

      assert template |> Liquex.render!(context) |> elem(0) |> IO.iodata_to_binary() == "A|draft,published"
    end

    test "a loop over a map reads an atom key and value as text" do
      context = Villain.create_context(%{"x" => TemplateView.wrap(%{kind: :lede})})

      {:ok, template} =
        Liquex.parse(
          ~S({% for pair in x %}{% if pair[0] == "kind" and pair[1] == "lede" %}{{ pair[0] }}={{ pair[1] }}{% endif %}{% endfor %})
        )

      assert template |> Liquex.render!(context) |> elem(0) |> IO.iodata_to_binary() == "kind=lede"
    end

    test "a filter's atom result reads as text" do
      context = Liquex.Context.new(%{"x" => TemplateView.wrap(%{title: "A"})}, filter_module: AtomFilters)

      {:ok, template} =
        Liquex.parse(
          ~S({% assign k = x | kind %}{% if k == "lede" %}{{ k }}{% endif %}{% assign ks = x | kinds %}{% if ks contains "lead" %}|{{ ks | join: "," }}{% endif %})
        )

      assert template |> Liquex.render!(context) |> elem(0) |> IO.iodata_to_binary() == "lede|lede,lead"
    end

    test "gives a tag the atom itself" do
      context = Villain.create_context(%{"x" => TemplateView.wrap(%{status: :draft})})
      assert TemplateView.eval({:field, [key: "x", key: "status"]}, context) == :draft
    end
  end
end
