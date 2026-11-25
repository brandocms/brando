defmodule Brando.Content.Proposals.TranslationWorkTest do
  # `translation_work` (#3744): a synchronized translation's open work as
  # units, a source's language versions and the units a new translation would
  # have, for the Assistant and over MCP. Not async: the MCP calls set the
  # endpoint's fetcher (`MCPHelpers.setup_fetcher/0`).
  use Brando.ConnCase, async: false

  import Brando.MCPHelpers

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Content.Proposals.Tools
  alias Brando.Content.Proposals.Tools.Context
  alias Brando.Factory
  alias Brando.MCP
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.TranslationFixtures
  alias Brando.Translations
  alias Brando.Translations.Work

  @type_name "Brando.SyncTest.Article"

  setup do
    user = Factory.insert(:random_user, role: :superuser)

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
      SyncTest.create_article(%{title: "Tittel", slug: "tittel", language: "no", status: "published"}, user)

    block = TranslationFixtures.add_block(source, module, user, "<p>Første avsnitt</p>", 0)
    %{user: user, module: module, source: source, block: block, context: %Context{actor: user}}
  end

  defp call!(args, context) do
    assert {:ok, result} = Tools.call("translation_work", args, context)
    assert {:ok, _} = Jason.encode(result)
    result
  end

  # Thirteen texts, too long together for one result
  defp long_translation(c) do
    {:ok, source} =
      SyncTest.create_article(%{title: "Lang", slug: "lang", language: "no", status: "published"}, c.user)

    for n <- 1..12,
        do: TranslationFixtures.add_block(source, c.module, c.user, String.duplicate("Tekst #{n}. ", 200), n)

    {:ok, target} = Translations.create_target(Article, source.id, :en, c.user)
    target
  end

  # The batches after `first`, each read after the last key of the one before
  defp rest_batches(target, first, c) do
    Stream.unfold(first.next_after, fn
      nil -> nil
      key -> (batch = call!(args(target.id, %{"after" => key}), c.context)) && {batch, batch.next_after}
    end)
    |> Enum.to_list()
  end

  defp args(id, extra \\ %{}), do: Map.merge(%{"content_type" => @type_name, "id" => id}, extra)

  describe "a synchronized translation" do
    test "restarts the read when a source transfer changes the target's role", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      event = BrandoIntegration.Repo.config()[:telemetry_prefix] ++ [:query]
      handler = make_ref()
      owner = self()

      :telemetry.attach(
        handler,
        event,
        fn _, _, metadata, _ ->
          if self() == owner and metadata.source == Article.__schema__(:source) and metadata.params == [c.source.id] and
               !Process.put(handler, true) do
            {:ok, _} = Translations.transfer_source(Article, target.id, c.user)
          end
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)
      result = Tools.call("translation_work", args(target.id), c.context)
      assert Process.get(handler)
      assert {:ok, %{role: "source"}} = result
    end

    test "lists its open work as units, with a token for the batch", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      result = call!(args(target.id), c.context)
      body = "entry_blocks/#{c.block.uid}/refs/body/text"

      assert %{
               role: "translation",
               language: "en",
               source: %{id: source_id, language: "no"},
               total: 2,
               next_after: nil,
               units: [title, body_unit],
               source_digest: token
             } = result

      assert source_id == c.source.id
      assert %{key: "title", kind: "translate", format: "plain", source: "Tittel"} = title
      assert %{key: ^body, format: "html", source: "<p>Første avsnitt</p>", block_uid: _} = body_unit
      assert is_binary(result.note)

      # The token is the one the check takes for these units
      {:ok, %{units: units}} = Work.translation_units(Article, target.id)
      scope = %{type: to_string(Article), id: target.id, language: "en"}
      texts = %{"title" => "Title", body => "<p>First paragraph</p>"}
      assert :ok = Work.check(token, scope, units, %{texts: texts, reviewed: []})
    end

    test "returns a long entry's work in batches, each with its own token", c do
      target = long_translation(c)

      first = call!(args(target.id), c.context)
      assert first.total == 13
      assert is_binary(first.next_after)
      assert byte_size(Jason.encode!(first)) < Brando.MCP.Tools.result_limit()

      rest =
        Stream.unfold(first.next_after, fn
          nil -> nil
          key -> (batch = call!(args(target.id, %{"after" => key}), c.context)) && {batch, batch.next_after}
        end)
        |> Enum.to_list()

      keys = Enum.flat_map([first | rest], fn batch -> Enum.map(batch.units, & &1.key) end)
      assert length(keys) == 13 and keys == Enum.uniq(keys)
      assert Enum.uniq(Enum.map([first | rest], & &1.source_digest)) |> length() == length([first | rest])
    end

    # A translate unit's copy is its source: sent once
    test "a long text is read whole, its copy not repeated", c do
      long = "<p>" <> String.duplicate("Et langt avsnitt med <strong>tekst</strong>. ", 270) <> "</p>"
      assert byte_size(long) > 11_000
      {:ok, source} = SyncTest.create_article(%{title: "T", slug: "t", language: "no", status: "published"}, c.user)
      TranslationFixtures.add_block(source, c.module, c.user, long, 1)
      {:ok, target} = Translations.create_target(Article, source.id, :en, c.user)

      first = call!(args(target.id), c.context)
      batches = [first | rest_batches(target, first, c)]
      assert Enum.all?(batches, &(byte_size(Jason.encode!(&1)) <= Brando.MCP.Tools.result_limit()))
      units = Enum.flat_map(batches, & &1.units)

      assert %{source: ^long, answerable: true} = unit = Enum.find(units, &(&1.source == long))
      refute Map.has_key?(unit, :current)
    end

    # Too long for any result: named, without its text, and left to the editor
    test "a text too long for a result is listed without it, and is not part of the batch", c do
      long = "<p>" <> String.duplicate("Et svært langt avsnitt. ", 1_200) <> "</p>"
      {:ok, source} = SyncTest.create_article(%{title: "T", slug: "t", language: "no", status: "published"}, c.user)
      block = TranslationFixtures.add_block(source, c.module, c.user, long, 1)
      {:ok, target} = Translations.create_target(Article, source.id, :en, c.user)
      key = "entry_blocks/#{block.uid}/refs/body/text"

      first = call!(args(target.id), c.context)
      batches = [first | rest_batches(target, first, c)]
      assert Enum.all?(batches, &(byte_size(Jason.encode!(&1)) <= Brando.MCP.Tools.result_limit()))
      result = Enum.find(batches, fn batch -> Enum.any?(batch.units, &(&1.key == key)) end)

      assert %{answerable: false, too_long: true, reason: reason, label: "Text › Body"} =
               unit = Enum.find(result.units, &(&1.key == key))

      assert is_binary(reason)
      refute Map.has_key?(unit, :source) or Map.has_key?(unit, :current)

      # Not missing from an answer to the batch, and refused when answered
      {:ok, %{units: now}} = Work.translation_units(Article, target.id)
      scope = %{type: to_string(Article), id: target.id, language: "en"}
      answer = Map.new(for %{answerable: true, key: k} <- result.units, do: {k, "T"})
      assert :ok = Work.check(result.source_digest, scope, now, %{texts: answer, reviewed: []})

      assert {:error, [%{code: "extra", key: ^key}]} =
               Work.check(result.source_digest, scope, now, %{texts: Map.put(answer, key, "<p>x</p>"), reviewed: []})
    end

    # The token, the other items and the head share the result with the units
    # The translation translated and saved, then the source's body changed
    defp reviewed_body(c, before, translated, now) do
      {:ok, source} = SyncTest.create_article(%{title: "T", slug: "t", language: "no", status: "published"}, c.user)
      block = TranslationFixtures.add_block(source, c.module, c.user, before, 1)
      {:ok, target} = Translations.create_target(Article, source.id, :en, c.user)
      key = "entry_blocks/#{block.uid}/refs/body/text"
      {:ok, _} = Translations.save_work(Article, target.id, %{texts: %{"title" => "T", key => translated}}, c.user)

      [ref] = Brando.Repo.preload(block, :refs).refs
      ref |> Ecto.Changeset.change(data: %{ref.data | data: %{ref.data.data | text: now}}) |> Brando.Repo.update!()
      {:ok, source} = Translations.load_entry(Article, source.id)
      Translations.source_saved(source)

      {target, key}
    end

    test "a review unit has the source's text before the change", c do
      {target, key} = reviewed_body(c, "<p>Første avsnitt</p>", "<p>First paragraph</p>", "<p>Første, endret</p>")

      assert %{units: [unit]} = call!(args(target.id), c.context)

      assert %{
               key: ^key,
               kind: "review",
               answerable: true,
               source_previous: "<p>Første avsnitt</p>",
               source: "<p>Første, endret</p>",
               current: "<p>First paragraph</p>"
             } = unit
    end

    test "a review unit that fits a result only without its previous text is read without it", c do
      # About 8 KB of text with its translation, and 12 KB before the change
      text = fn word -> "<p>" <> String.duplicate("#{word} ", 1_150) <> "</p>" end
      before = "<p>" <> String.duplicate("Gammel tekst ", 900) <> "</p>"
      {target, key} = reviewed_body(c, before, text.("Old"), text.("Ny"))

      result = call!(args(target.id), c.context)
      assert byte_size(Jason.encode!(result)) <= Brando.MCP.Tools.result_limit()

      assert [%{key: ^key, kind: "review", answerable: true, source: source} = unit] = result.units
      assert source == text.("Ny")
      refute Map.has_key?(unit, :source_previous)
    end

    test "a first batch with many links waiting for their targets stays within a result", c do
      {:ok, source} =
        SyncTest.create_article(%{title: "Mange", slug: "mange", language: "no", status: "published"}, c.user)

      blocks =
        for n <- 1..59, do: TranslationFixtures.add_block(source, c.module, c.user, "<p>Avsnitt nummer #{n}</p>", n)

      {:ok, target} = Translations.create_target(Article, source.id, :en, c.user)
      version = Translations.get_pending_version(Article, target.id)
      now = NaiveDateTime.utc_now(:second)

      Brando.Repo.insert_all(
        Brando.Translations.WorkItem,
        for {block, n} <- blocks |> Enum.take(40) |> Enum.with_index() do
          %{
            pending_version_id: version.id,
            path:
              "entry_blocks/#{block.uid}/vars/link_to_the_related_entry_shown_in_the_sidebar_beside_the_article_body_#{n}/identifier/#{100_000 + n}",
            kind: :awaiting_translation,
            inserted_at: now,
            updated_at: now
          }
        end
      )

      first = call!(args(target.id), c.context)
      assert first.total == 60 and first.other_total == 40
      assert byte_size(Jason.encode!(first)) <= Brando.MCP.Tools.result_limit()

      # The rest follows, and every unit is read once
      rest =
        Stream.unfold(first.next_after, fn
          nil -> nil
          key -> (batch = call!(args(target.id, %{"after" => key}), c.context)) && {batch, batch.next_after}
        end)
        |> Enum.to_list()

      assert [first | rest] |> Enum.flat_map(& &1.units) |> length() == 60
    end

    # Applying a batch resolves its units, so the open ones shrink: the next
    # batch follows a key's place in the entry, not a count
    test "the next batch starts after the last key read, though the batch read was applied", c do
      target = long_translation(c)
      first = call!(args(target.id), c.context)
      all = Enum.map(Work.translation_units(Article, target.id) |> elem(1) |> Map.get(:units), & &1.key)
      read = Enum.map(first.units, & &1.key)

      version = Translations.get_pending_version(Article, target.id)

      Brando.Repo.update_all(
        Ecto.Query.from(w in Brando.Translations.WorkItem,
          where: w.pending_version_id == ^version.id and w.path in ^read
        ),
        set: [resolved_at: DateTime.utc_now(:second)]
      )

      second = call!(args(target.id, %{"after" => first.next_after}), c.context)
      assert hd(second.units).key == Enum.at(all, length(read))
      refute Map.has_key?(second, :restarted)

      # A key no longer in the entry starts from the beginning, and says so
      again = call!(args(target.id, %{"after" => "entry_blocks/gone/refs/body/text"}), c.context)
      assert %{restarted: true} = again
      assert hd(again.units).key == Enum.at(all, length(read))
    end

    test "a cursor that cannot be followed is refused, not read as the first batch", c do
      target = long_translation(c)

      assert {:error, _} = Tools.call("translation_work", args(target.id, %{"offset" => 20}), c.context)
      assert {:error, _} = Tools.call("translation_work", args(target.id, %{"after" => 12}), c.context)
      assert %{units: [_ | _]} = call!(args(target.id, %{"after" => nil}), c.context)
    end

    test "a long title is cut where it names the entry, so every batch still fits", c do
      title = String.duplicate("Lang tittel ", 2_500)

      {:ok, source} =
        SyncTest.create_article(%{title: title, slug: "lang-tittel", language: "no", status: "published"}, c.user)

      {:ok, target} = Translations.create_target(Article, source.id, :en, c.user)

      result = call!(args(target.id), c.context)
      assert String.length(result.title) == 200
      assert byte_size(Jason.encode!(result)) <= Brando.MCP.Tools.result_limit()
    end

    test "an independent translation is described, without units", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      {:ok, _} = Translations.make_independent(Article, target.id, c.user)

      assert %{synchronized: false, language: "en", message: message} = result = call!(args(target.id), c.context)
      refute Map.has_key?(result, :units)
      assert message =~ "independent"
    end
  end

  describe "a synchronized source" do
    test "lists its language versions with their open work, and the languages without one", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)

      assert %{role: "source", language: "no", versions: [version], missing_languages: []} =
               call!(args(c.source.id), c.context)

      assert %{language: "en", id: id, synchronized: true, open: %{translate: 2}} = version
      assert id == target.id
    end

    test "gives the units a new translation in a missing language would have", c do
      assert %{missing_languages: ["en"]} = call!(args(c.source.id), c.context)

      result = call!(args(c.source.id, %{"language" => "en"}), c.context)
      assert %{role: "source", new_translation: "en", total: 2, units: units, source_digest: token} = result
      assert Enum.all?(units, &(&1.kind == "translate" and not Map.has_key?(&1, :block_uid)))

      # The keys are the work items the created translation gets
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      created = call!(args(target.id), c.context)
      assert Enum.map(units, & &1.key) == Enum.map(created.units, & &1.key)

      {:ok, %{units: now}} = Work.new_translation_units(Article, c.source.id)
      scope = %{type: to_string(Article), id: {:new, c.source.id}, language: "en"}
      assert :ok = Work.check(token, scope, now, %{texts: %{}, reviewed: Enum.map(units, & &1.key)})
    end

    test "points at an existing version, and refuses a language the type does not have", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)

      assert {:error, message} = Tools.call("translation_work", args(c.source.id, %{"language" => "en"}), c.context)
      assert message =~ "#{target.id}"
      assert {:error, _} = Tools.call("translation_work", args(c.source.id, %{"language" => "xx"}), c.context)
    end

    test "marks a version in the trash, without pointing at its work, and keeps its language taken", c do
      # Pages have a trash; synchronized for this test
      put_test_env(Brando.Pages.Page, translatable: [mode: :synchronized])
      page = Factory.insert(:page, title: "Om oss", uri: "om-oss", language: :no, creator: c.user)
      {:ok, target} = Translations.create_target(Brando.Pages.Page, page.id, :en, c.user)
      {:ok, _} = Brando.Pages.delete_page(target.id, c.user)
      page_args = &Map.merge(%{"content_type" => "Brando.Pages.Page", "id" => page.id}, &1)

      assert %{versions: [version], missing_languages: []} = call!(page_args.(%{}), c.context)
      assert %{language: "en", in_trash: true} = version
      refute Map.has_key?(version, :open)

      assert {:error, message} = Tools.call("translation_work", page_args.(%{"language" => "en"}), c.context)
      refute message =~ "#{target.id}"
      assert message =~ "trash"
    end

    test "an entry without translations yet is a source with every other language missing", c do
      assert %{role: "source", versions: [], missing_languages: ["en"]} = call!(args(c.source.id), c.context)
      assert %{new_translation: "en", total: 2} = call!(args(c.source.id, %{"language" => "en"}), c.context)
    end
  end

  test "an entry of a type that is not synchronized is described, without units", c do
    page = Factory.insert(:page, title: "Om oss", uri: "om-oss", language: :no, creator: c.user)

    assert %{synchronized: false, id: id, title: "Om oss", language: "no", message: message} =
             call!(%{"content_type" => "Brando.Pages.Page", "id" => page.id}, c.context)

    assert id == page.id
    assert message =~ "not synchronized"
  end

  # The notes tell a client how to answer a batch, and how one proposal
  # creates and fills in a missing language, with operations prepare_proposal
  # has
  test "names how to answer a batch, with operations prepare_proposal has", c do
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
    prepare = Enum.find(Tools.definitions(), &(&1.name == "prepare_proposal")).description

    for op <- ~w(translate create_translation), do: assert(prepare =~ ~s({"op":"#{op}"))

    for text <- [
          Enum.find(Tools.definitions(), &(&1.name == "translation_work")).description,
          call!(args(target.id), c.context).note
        ],
        do: assert(text =~ "translate operation" and text =~ "source_digest")

    {:ok, lone} = SyncTest.create_article(%{title: "Alene", slug: "alene", language: "no", status: "published"}, c.user)
    note = call!(args(lone.id, %{"language" => "en"}), c.context).note
    assert note =~ "create_translation" and note =~ ~s(translate on {"new": R})
  end

  test "is offered over MCP as a read, and to the Assistant" do
    # The tool sizes its results for this limit
    assert Brando.MCP.Tools.result_limit() == 24_000

    assert %{annotations: %{readOnlyHint: true, destructiveHint: false}} =
             Enum.find(MCP.Tools.list(), &(&1.name == "brando_content_translation_work"))

    assert Enum.any?(Tools.definitions(), &(&1.name == "translation_work"))
  end

  describe "with group authorization" do
    setup c do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      Boundary.put_scope(nil)
      setup_fetcher()
      {:ok, _} = Migration.run()
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      Map.merge(c, %{scope: Scope.standalone(c.user), target: target})
    end

    defp member(c, keys) do
      user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      {:ok, group} = Groups.create(c.scope, %{name: "Group #{System.unique_integer([:positive])}"}, keys)
      {:ok, :ok} = Groups.add_member(c.scope, group.id, user.id)
      user
    end

    @read_articles "brando.synctest_articles.read"

    test "someone who cannot read the translations gets nothing", c do
      user = member(c, ["brando.admin.access", "brando.assistant.use"])

      for id <- [c.target.id, c.source.id] do
        assert {:error, message} = Tools.call("translation_work", args(id), %Context{actor: user})
        refute message =~ "Tittel"
      end

      reader = member(c, ["brando.admin.access", "brando.assistant.use", @read_articles])
      assert {:ok, %{units: [_, _]}} = Tools.call("translation_work", args(c.target.id), %Context{actor: reader})
    end

    # The source's text is in every unit: a translation whose source the
    # person may not read is refused as if it did not exist
    test "someone who may read the translation and not its source gets nothing", c do
      alias Brando.SyncPolicyTest.Article, as: PolicyArticle

      reader = member(c, ["brando.admin.access", "brando.assistant.use", "authorization.policy_articles.read"])
      policy_args = &%{"content_type" => "Brando.SyncPolicyTest.Article", "id" => &1}

      translated = fn owner ->
        {:ok, source} =
          Brando.SyncPolicyTest.create_article(
            %{title: "Policy #{owner.id}", slug: "policy-#{owner.id}", language: "no", status: "published"},
            c.user
          )

        {:ok, target} = Translations.create_target(PolicyArticle, source.id, :en, c.user)

        # The policy reads the creator: the reader made the translation, `owner` the source
        Brando.Repo.update_all(
          Ecto.Query.from(a in PolicyArticle, where: a.id == ^source.id),
          set: [creator_id: owner.id]
        )

        Brando.Repo.update_all(
          Ecto.Query.from(a in PolicyArticle, where: a.id == ^target.id),
          set: [creator_id: reader.id]
        )

        target
      end

      # Both the reader's: the work is read
      own = translated.(reader)
      assert {:ok, %{units: [_]}} = Tools.call("translation_work", policy_args.(own.id), %Context{actor: reader})

      # The source someone else's: refused, and nothing of the source shows
      other = translated.(c.user)
      assert {:error, message} = Tools.call("translation_work", policy_args.(other.id), %Context{actor: reader})
      refute message =~ "Policy"
    end

    test "over MCP, the same", c do
      tenant = MCP.tenant(nil, nil) |> switch!()
      user = member(c, ["brando.admin.access", "brando.mcp.connect"]) |> enable_two_factor()
      %{"access_token" => token} = connect_directly(user, tenant)
      assert %{"result" => %{"isError" => true}} = call_tool(tenant, token, "translation_work", args(c.target.id))

      reader = member(c, ["brando.admin.access", "brando.mcp.connect", @read_articles]) |> enable_two_factor()
      %{"access_token" => token} = connect_directly(reader, tenant)

      assert %{"result" => %{"structuredContent" => %{"units" => [_, _], "source_digest" => _}}} =
               call_tool(tenant, token, "translation_work", args(c.target.id))
    end
  end
end
