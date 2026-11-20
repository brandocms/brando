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

  defp args(id, extra \\ %{}), do: Map.merge(%{"content_type" => @type_name, "id" => id}, extra)

  describe "a synchronized translation" do
    test "lists its open work as units, with a token for the batch", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      result = call!(args(target.id), c.context)
      body = "entry_blocks/#{c.block.uid}/refs/body/text"

      assert %{
               role: "translation",
               language: "en",
               source: %{id: source_id, language: "no"},
               total: 2,
               offset: 0,
               next_offset: nil,
               units: [title, body_unit],
               source_digest: token
             } = result

      assert source_id == c.source.id
      assert %{key: "title", kind: "translate", format: "plain", source: "Tittel", current: "Tittel"} = title
      assert %{key: ^body, format: "html", source: "<p>Første avsnitt</p>", block_uid: _} = body_unit
      assert result.note =~ "translate"

      # The token is the one the check takes for these units
      {:ok, %{units: units}} = Work.translation_units(Article, target.id)
      scope = %{type: to_string(Article), id: target.id, language: "en"}
      texts = %{"title" => "Title", body => "<p>First paragraph</p>"}
      assert :ok = Work.check(token, scope, units, %{texts: texts, reviewed: []})
    end

    test "returns a long entry's work in batches, each with its own token", c do
      {:ok, source} =
        SyncTest.create_article(%{title: "Lang", slug: "lang", language: "no", status: "published"}, c.user)

      for n <- 1..12,
          do: TranslationFixtures.add_block(source, c.module, c.user, String.duplicate("Tekst #{n}. ", 200), n)

      {:ok, target} = Translations.create_target(Article, source.id, :en, c.user)

      first = call!(args(target.id), c.context)
      assert first.total == 13
      assert is_integer(first.next_offset)
      assert byte_size(Jason.encode!(first)) < Brando.MCP.Tools.result_limit()

      rest =
        Stream.unfold(first.next_offset, fn
          nil -> nil
          offset -> (batch = call!(args(target.id, %{"offset" => offset}), c.context)) && {batch, batch.next_offset}
        end)
        |> Enum.to_list()

      keys = Enum.flat_map([first | rest], fn batch -> Enum.map(batch.units, & &1.key) end)
      assert length(keys) == 13 and keys == Enum.uniq(keys)
      assert Enum.uniq(Enum.map([first | rest], & &1.source_digest)) |> length() == length([first | rest])
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

      {:ok, now} = Work.new_translation_units(Article, c.source.id)
      scope = %{type: to_string(Article), id: {:new, c.source.id}, language: "en"}
      assert :ok = Work.check(token, scope, now, %{texts: %{}, reviewed: Enum.map(units, & &1.key)})
    end

    test "points at an existing version, and refuses a language the type does not have", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)

      assert {:error, message} = Tools.call("translation_work", args(c.source.id, %{"language" => "en"}), c.context)
      assert message =~ "#{target.id}"
      assert {:error, _} = Tools.call("translation_work", args(c.source.id, %{"language" => "xx"}), c.context)
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

  test "is offered over MCP as a read, and to the Assistant" do
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
