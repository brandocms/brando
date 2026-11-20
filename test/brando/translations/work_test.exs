defmodule Brando.Translations.WorkTest do
  # A synchronized translation's open work as units (#3744): read from the
  # pending version, keyed by sync path, batched, and the token and check a
  # translate answer goes through.
  use Brando.ConnCase, async: true

  alias Brando.Content.Block
  alias Brando.Content.TableRow
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.Translations
  alias Brando.Translations.Work

  @body ~s(<p>Første <a href="https://example.com/">avsnitt</a> for {{ entry.title }}</p>)

  setup do
    user = Factory.insert(:random_user)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Text"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.body %}",
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Default"}}}]
        ),
        user
      )

    {:ok, source} =
      SyncTest.create_article(
        %{
          title: "Tittel",
          slug: "tittel",
          language: "no",
          status: "published",
          subtitle: "",
          items: [%{label: "Første punkt", link: "/a"}]
        },
        user
      )

    block = add_block(source, module, user)
    %{user: user, module: module, source: source, block: block}
  end

  # Every kind of text a block holds: a rich text, a header, Markdown, a
  # picture's title and alt text, string, rich text and link variables, and
  # a table row's cell.
  defp add_block(article, module, user) do
    ref = fn name, type, data ->
      %{"uid" => Brando.Utils.generate_uid(), "name" => name, "data" => %{"type" => type, "data" => data}}
    end

    params = %{
      "uid" => Brando.Utils.generate_uid(),
      "type" => "module",
      "module_id" => module.id,
      "creator_id" => user.id,
      "source" => to_string(Article.Blocks),
      "refs" => [
        ref.("body", "text", %{"text" => @body}),
        ref.("heading", "header", %{"text" => "Overskrift"}),
        ref.("notes", "markdown", %{"text" => "**Merk** dette"}),
        ref.("photo", "picture", %{"title" => "Bildetittel", "alt" => "Bilde", "credits" => ""})
      ]
    }

    block = %Block{} |> Block.recursive_block_changeset(params, user) |> Repo.insert!()

    for {var, index} <-
          Enum.with_index([
            %Var{key: "kicker", type: :string, value: "Stikktittel"},
            %Var{key: "intro", type: :rich_text, value: "<p>Innledning</p>"},
            %Var{key: "cta", type: :link, link_type: :url, value: "/no/om-oss", link_text: "Les mer"}
          ]),
        do: Repo.insert!(%{var | label: %{"en" => var.key}, block_id: block.id, sequence: index})

    row = Repo.insert!(%TableRow{block_id: block.id, sync_uid: "row1", sequence: 0})

    Repo.insert!(%Var{
      key: "cell",
      type: :string,
      value: "Celle",
      label: %{"en" => "cell"},
      table_row_id: row.id,
      sequence: 0
    })

    struct(Article.Blocks, %{entry_id: article.id, block_id: block.id, sequence: 0}) |> Repo.insert!()
    block
  end

  defp load(id) do
    {:ok, entry} = Translations.load_entry(Article, id)
    entry
  end

  defp units(target) do
    {:ok, %{units: units}} = Work.translation_units(Article, target.id)
    units
  end

  defp by_key(units), do: Map.new(units, &{&1.key, &1})

  defp scope(target), do: %{type: to_string(Article), id: target.id, language: "en"}

  defp set_body(article_id, text) do
    [join | _] = load(article_id).entry_blocks
    ref = Enum.find(Repo.preload(join.block, :refs, force: true).refs, &(&1.name == "body"))
    ref |> Ecto.Changeset.change(data: %{ref.data | data: %{ref.data.data | text: text}}) |> Repo.update!()
  end

  defp target_block_uid(target), do: hd(load(target.id).entry_blocks).block.uid

  describe "a new translation's units" do
    test "are its open work items, with the source's text, its format and where it is", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      units = units(target)
      prefix = "entry_blocks/#{c.block.uid}"
      item = hd(load(c.source.id).items).uid

      # The keys are the work items' paths
      paths = Translations.get_pending_version(Article, target.id).work_items |> Enum.map(& &1.path) |> Enum.sort()
      assert units |> Enum.map(& &1.key) |> Enum.sort() == paths

      expected = %{
        "title" => {"plain", "Tittel"},
        "items/#{item}/label" => {"plain", "Første punkt"},
        "items/#{item}/link" => {"plain", "/a"},
        "#{prefix}/refs/body/text" => {"html", @body},
        "#{prefix}/refs/heading/text" => {"plain", "Overskrift"},
        "#{prefix}/refs/notes/text" => {"markdown", "**Merk** dette"},
        "#{prefix}/refs/photo/title" => {"plain", "Bildetittel"},
        "#{prefix}/refs/photo/alt" => {"plain", "Bilde"},
        "#{prefix}/vars/kicker/value" => {"plain", "Stikktittel"},
        "#{prefix}/vars/intro/value" => {"html", "<p>Innledning</p>"},
        "#{prefix}/vars/cta/link_text" => {"plain", "Les mer"},
        "#{prefix}/vars/cta/url" => {"plain", "/no/om-oss"},
        "#{prefix}/rows/row1/vars/cell/value" => {"plain", "Celle"}
      }

      assert Map.new(units, &{&1.key, {&1.format, &1.source}}) == expected
      assert Enum.all?(units, &(&1.kind == "translate" and &1.answerable and &1.current == &1.source))

      # A block unit names the translation's own block, a field none
      units = by_key(units)
      block_uid = target_block_uid(target)
      refute block_uid == c.block.uid
      assert units["#{prefix}/refs/body/text"].block_uid == block_uid
      refute Map.has_key?(units["title"], :block_uid)

      # Labelled as the form's work list labels them
      assert units["#{prefix}/refs/body/text"].label == "Text › Body"
      assert units["#{prefix}/rows/row1/vars/cell/value"].label == "Text › Table › Cell"
      assert units["title"].label == "Title"

      # In the entry's order: the title before the blocks
      assert hd(units(target)).key == "title"
    end

    test "a text changed in the source after it was translated is to review, with both texts", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      version = Translations.get_pending_version(Article, target.id)
      body = "entry_blocks/#{c.block.uid}/refs/body/text"

      set_body(target.id, "<p>First paragraph</p>")
      {:ok, _} = Translations.target_saved(Article, target.id, %{version_id: version.id, acknowledged: []})
      refute Map.has_key?(by_key(units(target)), body)

      set_body(c.source.id, "<p>Første avsnitt, endret</p>")
      Translations.source_saved(load(c.source.id))

      assert %{kind: "review", source: "<p>Første avsnitt, endret</p>", current: "<p>First paragraph</p>"} =
               by_key(units(target))[body]
    end

    test "a link waiting for its target's translation is listed, not answerable", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      version = Translations.get_pending_version(Article, target.id)

      Repo.insert_all(Brando.Translations.WorkItem, [
        %{
          pending_version_id: version.id,
          path: "entry_blocks/#{c.block.uid}/identifiers/99",
          kind: :awaiting_translation,
          inserted_at: NaiveDateTime.utc_now(:second),
          updated_at: NaiveDateTime.utc_now(:second)
        }
      ])

      assert [%{kind: "awaiting_translation", answerable: false} = other] =
               Enum.reject(units(target), & &1.answerable)

      assert other.block_uid == target_block_uid(target)
      refute Map.has_key?(other, :source)
    end
  end

  # Units name blocks and rows by the identity `Sync` gives them
  describe "identities" do
    defp text_items(entry, suffix) do
      for {path, :text, _} <- Brando.Translations.Sync.flatten_entry(entry, Article),
          String.ends_with?(path, suffix),
          do: %{path: path, kind: :translate}
    end

    test "two blocks with the same sync_uid: the second is named by its uid, as Sync names it", c do
      second = Brando.TranslationFixtures.add_block(c.source, c.module, c.user, "<p>Andre</p>", 1)

      for block <- [c.block, second],
          do: block |> Ecto.Changeset.change(sync_uid: "dup") |> Repo.update!()

      source = load(c.source.id)
      items = text_items(source, "/refs/body/text")

      assert Enum.map(items, & &1.path) == [
               "entry_blocks/dup/refs/body/text",
               "entry_blocks/#{second.uid}/refs/body/text"
             ]

      assert [first_unit, second_unit] = Work.units(Article, source, source, items)
      assert %{block_uid: first_uid, format: "html", source: @body} = first_unit
      assert first_uid == c.block.uid
      assert %{block_uid: second_uid, format: "html", source: "<p>Andre</p>"} = second_unit
      assert second_uid == second.uid
    end

    test "a table row without sync_uid is found by its position, as Sync keys it", c do
      row = Repo.insert!(%TableRow{block_id: c.block.id, sequence: 1})

      Repo.insert!(%Var{
        key: "note",
        type: :rich_text,
        value: "<p>Merknad</p>",
        label: %{"en" => "note"},
        table_row_id: row.id,
        sequence: 0
      })

      source = load(c.source.id)
      assert [%{path: path} = item] = text_items(source, "/vars/note/value")
      assert path =~ "/rows/#"
      assert [%{format: "html"}] = Work.units(Article, source, source, [item])
    end
  end

  test "a source's units for a missing language are those its new translation gets", c do
    {:ok, %{units: prospective}} = Work.new_translation_units(Article, c.source.id)
    assert Enum.all?(prospective, &(&1.kind == "translate" and not Map.has_key?(&1, :block_uid)))

    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
    created = units(target)

    assert Enum.map(prospective, & &1.key) == Enum.map(created, & &1.key)
    assert Enum.map(prospective, &Map.delete(&1, :block_uid)) == Enum.map(created, &Map.delete(&1, :block_uid))
  end

  test "an entry outside a group, a source and an independent translation have no units", c do
    assert {:error, :unlinked} = Work.translation_units(Article, c.source.id)
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
    assert {:error, :source} = Work.translation_units(Article, c.source.id)
    {:ok, _} = Translations.make_independent(Article, target.id, c.user)
    assert {:error, :independent} = Work.translation_units(Article, target.id)
    assert {:error, :not_synchronized} = Work.translation_units(Brando.Pages.Page, 1)
  end

  describe "batch/4" do
    defp unit(n, text \\ "Tekst"),
      do: %{
        key: "k#{String.pad_leading(to_string(n), 2, "0")}",
        kind: "translate",
        answerable: true,
        label: "L",
        format: "plain",
        source: text,
        current: text
      }

    defp positions(units), do: units |> Enum.with_index() |> Map.new(fn {unit, index} -> {unit.key, index} end)

    defp keys(%{units: units}), do: Enum.map(units, & &1.key)

    test "splits the units by size, each batch following the last key read" do
      units = Enum.map(1..30, &unit/1)
      positions = positions(units)
      size = byte_size(Jason.encode!(unit(1))) + 1 + Work.token_bytes(unit(1))

      assert %{more: true, restarted: false} = first = Work.batch(units, positions, nil, size * 10)
      assert keys(first) == Enum.map(1..10, &unit(&1).key)
      assert %{more: true} = second = Work.batch(units, positions, "k10", size * 10)
      assert hd(keys(second)) == "k11"
      assert %{more: false} = Work.batch(units, positions, "k20", size * 10)
      assert %{units: [], more: false} = Work.batch(units, positions, "k30", size * 10)
      assert %{units: limited, more: true} = Work.batch(units, positions, nil, size * 10, max_units: 5)
      assert length(limited) == 5
    end

    test "follows a key that is no longer open by its place in the entry" do
      all = Enum.map(1..30, &unit/1)
      positions = positions(all)
      # The first ten were answered and resolved
      open = Enum.drop(all, 10)

      assert %{restarted: false} = batch = Work.batch(open, positions, "k10", 10_000)
      assert hd(keys(batch)) == "k11"
    end

    test "starts from the first unit after a key the entry no longer has, and says so" do
      units = Enum.map(1..3, &unit/1)
      assert %{restarted: true, units: [%{key: "k01"} | _]} = Work.batch(units, positions(units), "gone", 10_000)
    end

    test "returns a unit larger than a batch alone and whole" do
      long = String.duplicate("Lang tekst. ", 2_000)
      units = [unit(1), unit(2, long), unit(3)]
      positions = positions(units)

      assert %{units: [%{key: "k01"}], more: true} = Work.batch(units, positions, nil, 500)
      assert %{units: [%{key: "k02", source: ^long}], more: true} = Work.batch(units, positions, "k01", 500)
      assert %{units: [%{key: "k03"}], more: false} = Work.batch(units, positions, "k02", 500)
    end
  end

  describe "check/4" do
    setup c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      units = units(target)
      %{target: target, units: units, token: Work.token(scope(target), units)}
    end

    defp all_texts(units), do: Map.new(units, &{&1.key, &1.source})

    test "accepts every unit answered, with its markup and placeholders kept", c do
      body = "entry_blocks/#{c.block.uid}/refs/body/text"
      texts = c.units |> all_texts() |> Map.drop(["title", body])

      texts =
        Map.put(texts, body, ~s(<p>First <a href="https://example.com/">paragraph</a> for {{ entry.title }}</p>))

      assert :ok = Work.check(c.token, scope(c.target), c.units, %{texts: texts, reviewed: ["title"]})
    end

    test "refuses an answer to a unit whose source changed since it was read, naming it", c do
      body = "entry_blocks/#{c.block.uid}/refs/body/text"
      set_body(c.source.id, "<p>Endret</p>")
      Translations.source_saved(load(c.source.id))

      assert {:error, [%{key: ^body, code: "source_changed"}]} =
               Work.check(c.token, scope(c.target), units(c.target), %{texts: all_texts(c.units), reviewed: []})
    end

    test "refuses extra, missing and twice-answered keys, all at once", c do
      [first, second | _] = Enum.map(c.units, & &1.key)
      texts = c.units |> all_texts() |> Map.delete(second) |> Map.put("made/up", "x")

      assert {:error, problems} =
               Work.check(c.token, scope(c.target), c.units, %{texts: texts, reviewed: [first]})

      assert Enum.sort(Enum.map(problems, &{&1.code, &1.key})) ==
               Enum.sort([{"duplicate", first}, {"extra", "made/up"}, {"missing", second}])

      assert Enum.all?(problems, &is_binary(&1.message))
    end

    test "refuses a token for another entry, another language or one that was changed", c do
      answer = %{texts: all_texts(c.units), reviewed: []}

      for scope <- [%{scope(c.target) | id: c.source.id}, %{scope(c.target) | language: "de"}] do
        assert {:error, [%{code: "stale", key: nil}]} = Work.check(c.token, scope, c.units, answer)
      end

      {:ok, <<head::binary-size(20), byte, rest::binary>>} = Base.url_decode64(c.token, padding: false)
      tampered = Base.url_encode64(<<head::binary, Bitwise.bxor(byte, 1), rest::binary>>, padding: false)

      for token <- [tampered, "not a token", "", nil, String.slice(c.token, 0, 10)] do
        assert {:error, [%{code: "stale"}]} = Work.check(token, scope(c.target), c.units, answer)
      end
    end

    test "refuses lost markup or placeholders per unit", c do
      body = "entry_blocks/#{c.block.uid}/refs/body/text"
      intro = "entry_blocks/#{c.block.uid}/vars/intro/value"

      texts =
        c.units
        |> all_texts()
        |> Map.merge(%{
          body => "<div>First paragraph for {{ entry.name }}</div>",
          intro => "Introduction",
          "title" => "Title {% if x %}"
        })

      assert {:error, problems} = Work.check(c.token, scope(c.target), c.units, %{texts: texts, reviewed: []})

      assert Enum.sort(Enum.map(problems, &{&1.key, &1.code})) ==
               Enum.sort([
                 {body, "html_changed"},
                 {body, "placeholders_changed"},
                 {intro, "html_changed"},
                 {"title", "placeholders_changed"}
               ])
    end

    test "refuses a wrongly shaped answer as a problem, without raising", c do
      for answer <- [
            %{texts: %{}, reviewed: "title"},
            %{texts: ["title"], reviewed: []},
            %{texts: "Title", reviewed: nil},
            %{texts: %{}, reviewed: [12]}
          ] do
        assert {:error, problems} = Work.check(c.token, scope(c.target), c.units, answer)
        assert Enum.any?(problems, &(&1.code == "malformed"))
      end
    end

    test "refuses an empty or non-text answer", c do
      texts = c.units |> all_texts() |> Map.merge(%{"title" => " "})
      [_, second | _] = Enum.map(c.units, & &1.key)
      texts = Map.put(texts, second, 12)

      assert {:error, problems} = Work.check(c.token, scope(c.target), c.units, %{texts: texts, reviewed: []})
      assert Enum.sort(Enum.map(problems, &{&1.key, &1.code})) == Enum.sort([{"title", "blank"}, {second, "not_text"}])
    end
  end

  # Ported from BrandoMCP's translation validator (brandocms/brando_mcp@b7a3e40)
  describe "markup and placeholders" do
    defp check_one(source, text) do
      units = [%{key: "body", kind: "translate", answerable: true, label: "Body", format: "html", source: source}]
      scope = %{type: "Demo.Article", id: 1, language: "en"}
      Work.check(Work.token(scope, units), scope, units, %{texts: %{"body" => text}, reviewed: []})
    end

    test "accepts preserved markup" do
      assert :ok = check_one(~s(<p class="lead">Hello {{ name }}</p>), ~s(<p class="lead">Hei {{ name }}</p>))
      assert :ok = check_one("Welcome", "Velkommen")
      assert :ok = check_one("Hi <% user %> {% if a %}x{% endif %}", "Hei {% if a %}x{% endif %} <% user %>")
    end

    test "rejects changed HTML or placeholders" do
      assert {:error, problems} = check_one(~s(<p class="lead">Hello {{ name }}</p>), "<div>Hei {{ person }}</div>")
      assert Enum.map(problems, & &1.code) == ["html_changed", "placeholders_changed"]
      assert {:error, [%{code: "html_changed"}]} = check_one(~s(<p class="lead">Hello</p>), "<p>Hei</p>")
      assert {:error, [%{code: "placeholders_changed"}]} = check_one("Plain", "Plain {{ added }}")
    end
  end
end
