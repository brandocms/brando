defmodule Brando.Content.Proposals.AutoApplyTest do
  # A connection set to apply unpublished translations without review
  # (`Brando.Content.Proposals.AutoApply`): `prepare_proposal` with
  # `apply: "if_allowed"` as `Brando.MCP.Tools` calls it, for the connection
  # that authenticated the call. Synchronous: the endpoint's switch is one
  # row for the installation, which every test here writes.
  use Brando.LiveCase

  import Brando.MCPHelpers, only: [enable_two_factor: 1, switch!: 1, switch!: 2]
  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.Authorization.{Boundary, Catalog, Groups, Migration, Scope}
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.AutoApply
  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Proposals.Receipt
  alias Brando.Content.Proposals.Record
  alias Brando.Content.Proposals.Tools, as: Registry
  alias Brando.Content.Proposals.Translate
  alias Brando.Content.Transfer.Error
  alias Brando.MCP
  alias Brando.MCP.Grant
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.TranslationFixtures
  alias Brando.Translations
  alias Brando.Translations.Work
  alias BrandoAdmin.Components.Activity, as: Events

  @article "Brando.SyncTest.Article"
  @english %{"Tittel" => "Title", "<p>Første avsnitt</p>" => "<p>First paragraph</p>"}

  setup %{current_user: user} do
    enable_two_factor(user)
    tenant = MCP.tenant(nil, nil) |> switch!()

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Text"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.body %}",
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: ""}}}]
        ),
        user
      )

    source = article!(user, module)
    %{tenant: tenant, module: module, source: source, user: user}
  end

  defp article!(user, module) do
    {:ok, source} =
      SyncTest.create_article(
        %{title: "Tittel", slug: "tittel-#{System.unique_integer([:positive])}", language: "no", status: "published"},
        user
      )

    TranslationFixtures.add_block(source, module, user, "<p>Første avsnitt</p>", 0)
    source
  end

  defp grant!(user, tenant, opts \\ []) do
    Repo.insert!(%Grant{
      user_id: user.id,
      site_id: opts[:site_id],
      environment_id: opts[:environment_id],
      resource: Keyword.get(opts, :resource, MCP.resource(tenant)),
      client_id: "https://client.example/meta.json",
      client_name: Keyword.get(opts, :client, "Test Client"),
      redirect_uri: "https://client.example/cb",
      scope: MCP.scope(),
      auto_apply: Keyword.get(opts, :auto_apply, "none")
    })
  end

  defp allowed!(c, opts \\ []), do: grant!(c.user, c.tenant, Keyword.put(opts, :auto_apply, AutoApply.kind()))

  # A tool call as the endpoint makes it, for `grant`
  defp call(c, grant, name, args, user \\ nil) do
    auth = %{user: user || c.user, grant: grant, token: %{id: nil}}
    assert {:ok, result} = MCP.Tools.call("brando_content_" <> name, args, auth, c.tenant)
    result
  end

  defp prepare(c, grant, operations, extra \\ %{"apply" => "if_allowed"}, user \\ nil) do
    args = Map.merge(%{"summary" => "Translate into English", "operations" => operations}, extra)
    result = call(c, grant, "prepare_proposal", args, user)
    refute result[:isError], inspect(result)
    result.structuredContent
  end

  defp create(source, ref \\ "english", language \\ "en"),
    do: %{
      "op" => "create_translation",
      "source" => %{"content_type" => @article, "id" => source.id},
      "language" => language,
      "ref" => ref
    }

  # translate of the translation `ref` creates, with every unit answered
  defp translate(c, source, ref \\ "english") do
    {:ok, work} =
      Registry.call(
        "translation_work",
        %{"content_type" => @article, "id" => source.id, "language" => "en"},
        %Registry.Context{actor: c.user}
      )

    work = work |> Jason.encode!() |> Jason.decode!()

    %{
      "op" => "translate",
      "target" => %{"new" => ref},
      "source_digest" => work["source_digest"],
      "texts" => Map.new(work["units"], &{&1["key"], Map.fetch!(@english, &1["source"])})
    }
  end

  defp record(id), do: Repo.get!(Record, id)
  defp translated?(source), do: Translations.get_member(Article, source.id) != nil
  defp receipt?(id), do: Repo.exists?(from(r in Receipt, where: r.id == ^id))

  # Waits for review as any proposal does: pending, unapproved, nothing of
  # the attempt kept, the reason apart from its problems
  defp assert_waiting(c, result, reason) do
    assert %{"applied" => false, "not_applied" => not_applied, "review_url" => _} = result
    assert not_applied =~ reason
    assert result["note"] =~ "Nothing is saved yet"

    assert %Record{status: "pending", approved_at: nil, problems: [], auto_applied_grant_id: nil} =
             stored = record(result["proposal_id"])

    assert stored.auto_apply_reason == not_applied
    refute translated?(c.source)
    refute receipt?(result["proposal_id"])
    stored
  end

  describe "the setting" do
    test "a connection applies nothing without review until it is set", c do
      grant = grant!(c.user, c.tenant)
      assert %Grant{auto_apply: "none", auto_apply_set_by_id: nil, auto_apply_set_at: nil} = Repo.get!(Grant, grant.id)

      result = prepare(c, grant, [create(c.source), translate(c, c.source)])
      assert_waiting(c, result, "not set to apply")
    end

    test "only those who manage connections set it, either way, and it is recorded", c do
      grant = grant!(c.user, c.tenant)
      editor = Factory.insert(:random_user, role: :user)

      assert MCP.set_auto_apply(grant.id, AutoApply.kind(), editor) == {:error, :forbidden}
      assert MCP.set_auto_apply(grant.id, "everything", c.user) == {:error, :invalid}
      assert MCP.set_auto_apply(0, AutoApply.kind(), c.user) == {:error, :not_found}
      assert %Grant{auto_apply: "none"} = Repo.get!(Grant, grant.id)

      assert MCP.set_auto_apply(grant.id, AutoApply.kind(), c.user) == :ok
      user_id = c.user.id
      assert %Grant{auto_apply: "unpublished_translations", auto_apply_set_by_id: ^user_id} = Repo.get!(Grant, grant.id)

      assert MCP.set_auto_apply(grant.id, "none", c.user) == :ok
      assert %Grant{auto_apply: "none", auto_apply_set_at: %DateTime{}} = Repo.get!(Grant, grant.id)

      details =
        Repo.all(
          from(e in Event,
            where: e.schema == ^to_string(Grant) and e.entry_id == ^grant.id,
            order_by: e.id,
            select: e.details
          )
        )

      assert [%{"auto_apply" => "unpublished_translations"}, %{"auto_apply" => "none"}] = details

      MCP.revoke_grant(grant, c.user, "admin")
      assert MCP.set_auto_apply(grant.id, AutoApply.kind(), c.user) == {:error, :not_found}
    end
  end

  describe "a qualifying proposal" do
    test "is applied as the person, unpublished, and the small result names the created entry", c do
      grant = allowed!(c)
      result = prepare(c, grant, [create(c.source), translate(c, c.source)])

      assert %{"applied" => true, "status" => "applied", "created" => %{"english" => id}} = result
      refute Map.has_key?(result, "review_url")
      refute inspect(result) =~ "Nothing is saved"
      # Ids, not entries: a lost answer costs little to read again
      assert byte_size(Jason.encode!(result)) < 600

      translation = Repo.get!(Article, id)
      assert %{status: :draft, title: "Title", language: :en} = translation
      assert %{role: :target, synchronized: true} = Translations.get_member(Article, id)

      grant_id = grant.id

      assert %Record{status: "applied", approved_at: nil, auto_applied_grant_id: ^grant_id} =
               record(result["proposal_id"])

      assert receipt?(result["proposal_id"])
    end

    test "a create_translation alone is applied too", c do
      result = prepare(c, allowed!(c), [create(c.source)])
      assert %{"applied" => true, "created" => %{"english" => id}} = result
      assert %{status: :draft} = Repo.get!(Article, id)
    end

    test "without apply it waits for review, though the connection allows it", c do
      result = prepare(c, allowed!(c), [create(c.source)], %{})
      refute Map.has_key?(result, "applied")
      assert %Record{status: "pending", auto_apply_reason: nil} = record(result["proposal_id"])
      refute translated?(c.source)
    end

    test "apply takes only if_allowed", c do
      args = %{"summary" => "Translate", "operations" => [create(c.source)], "apply" => "always"}
      assert %{isError: true, structuredContent: %{"error" => error}} = call(c, allowed!(c), "prepare_proposal", args)
      assert error =~ "if_allowed"
      refute Repo.exists?(Record)
    end
  end

  describe "a proposal that does more waits for review" do
    setup c, do: Map.put(c, :grant, allowed!(c))

    test "a set_fields with a status", c do
      op = %{
        "op" => "set_fields",
        "target" => %{"content_type" => @article, "id" => c.source.id},
        "fields" => %{"status" => "draft"}
      }

      assert_waiting(c, prepare(c, c.grant, [create(c.source), op]), "only a proposal whose every operation")
    end

    test "a change to the source", c do
      op = %{
        "op" => "set_fields",
        "target" => %{"content_type" => @article, "id" => c.source.id},
        "fields" => %{"title" => "Ny"}
      }

      assert_waiting(c, prepare(c, c.grant, [create(c.source), op]), "only a proposal whose every operation")
    end

    test "a block change", c do
      [%{block: %{uid: uid}}] = Repo.preload(c.source, entry_blocks: :block).entry_blocks

      op = %{
        "op" => "set_block_active",
        "target" => %{"content_type" => @article, "id" => c.source.id},
        "block_uid" => uid,
        "active" => false
      }

      assert_waiting(c, prepare(c, c.grant, [create(c.source), op]), "only a proposal whose every operation")
    end

    test "a translate of a translation that exists", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      {:ok, %{units: units}} = Work.translation_units(Article, target.id)
      units = Enum.filter(units, & &1.answerable)

      op = %Translate{
        target: {Article, target.id},
        source_digest: Work.token(%{type: to_string(Article), id: target.id, language: "en"}, units),
        texts: Map.new(units, &{&1.key, Map.fetch!(@english, &1.source)}),
        reviewed: []
      }

      assert {:ok, proposal} = Proposals.propose([op], c.user, origin: :mcp, client: "Test Client", replaces: :latest)
      assert proposal.problems == []

      assert {:waiting, reason} = AutoApply.run(proposal.id, 1, c.user, c.grant.id, c.tenant)
      assert reason =~ "only a proposal whose every operation"
      assert %Record{status: "pending", auto_apply_reason: ^reason} = record(proposal.id)
      assert Repo.get!(Article, target.id).title == "Tittel"
    end

    test "an unknown operation is refused, as without apply", c do
      args = %{"summary" => "Sync", "operations" => [%{"op" => "sync_translation"}], "apply" => "if_allowed"}
      assert %{isError: true} = call(c, c.grant, "prepare_proposal", args)
      refute Repo.exists?(Record)
    end

    test "only operations that create translations qualify, read from the stored operations" do
      create = %{"op" => "create_translation", "ref" => "en"}
      refute AutoApply.qualifies?([])
      refute AutoApply.qualifies?(nil)
      assert AutoApply.qualifies?([create, %{"op" => "translate", "target" => %{"new" => "en"}}])
      refute AutoApply.qualifies?([create, %{"op" => "translate", "target" => %{"new" => "other"}}])
      refute AutoApply.qualifies?([create, %{"op" => "translate", "target" => %{"content_type" => @article, "id" => 1}}])
      refute AutoApply.qualifies?([create, %{"op" => "create_entry", "ref" => "x"}])
    end
  end

  describe "the connection" do
    test "revoked, reset or turned off after the call was authenticated, it applies nothing", c do
      grant = allowed!(c)
      MCP.revoke_grant(grant, c.user, "admin")
      assert_waiting(c, prepare(c, grant, [create(c.source)]), "only a connected tool")

      grant = allowed!(c)
      :ok = MCP.set_auto_apply(grant.id, "none", c.user)
      assert_waiting(c, prepare(c, grant, [create(c.source)]), "not set to apply")

      grant = allowed!(c)
      switch!(c.tenant, false)
      assert_waiting(c, prepare(c, grant, [create(c.source)]), "only a connected tool")
    end

    test "each of two connections of the same person and client follows its own setting", c do
      held_back = grant!(c.user, c.tenant)
      allowed = allowed!(c)

      assert_waiting(c, prepare(c, held_back, [create(c.source)]), "not set to apply")
      assert %{"applied" => true} = prepare(c, allowed, [create(c.source, "english")])
    end

    test "another site environment's connection cannot apply here", c do
      {:ok, site} =
        Brando.Tenant.Registry.create_site(%{
          name: "Other",
          key: "other#{System.unique_integer([:positive])}",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      {:ok, environment} =
        Brando.Tenant.Registry.create_environment(site, %{name: "production", key: "production", live: true})

      other = allowed!(c, site_id: site.id, environment_id: environment.id, resource: "https://other.example/mcp")
      assert_waiting(c, prepare(c, other, [create(c.source)]), "only a connected tool")
    end

    test "a site suspended after the call was authenticated applies nothing", c do
      {:ok, site} =
        Brando.Tenant.Registry.create_site(%{
          name: "Other",
          key: "other#{System.unique_integer([:positive])}",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      {:ok, environment} =
        Brando.Tenant.Registry.create_environment(site, %{name: "production", key: "production", live: true})

      # The site as the request was authenticated, active then
      tenant = MCP.tenant(site, environment) |> switch!()
      grant = allowed!(c, site_id: site.id, environment_id: environment.id, resource: MCP.resource(tenant))

      assert {:ok, {:ok, _grant}} =
               Repo.transaction(fn -> MCP.lock_auto_apply(grant.id, AutoApply.kind(), tenant) end)

      {:ok, _site} = Brando.Tenant.Registry.update_site(site, %{status: :suspended})

      assert {:ok, {:error, _reason}} =
               Repo.transaction(fn -> MCP.lock_auto_apply(grant.id, AutoApply.kind(), tenant) end)
    end

    test "the Assistant and the development server never apply, whatever they pass", c do
      args = %{"summary" => "Translate", "operations" => [create(c.source)], "apply" => "if_allowed"}

      assert {:ok, result} = Registry.call("prepare_proposal", args, %Registry.Context{actor: c.user})
      assert %{applied: false, not_applied: reason} = result
      assert reason =~ "only a connected tool"

      context = %Registry.Context{actor: c.user, conversation_id: Ecto.UUID.generate(), origin: :assistant}
      assert {:ok, %{applied: false}} = Registry.call("prepare_proposal", args, context)
      refute translated?(c.source)
    end
  end

  describe "applying" do
    test "a failure on the second copy of a batch leaves nothing of the attempt", c do
      other = article!(c.user, c.module)
      Process.put({:synctest_duplicate, other.id}, :error)
      jobs = Repo.aggregate(Oban.Job, :count)
      articles = Repo.aggregate(Article, :count)

      result = prepare(c, allowed!(c), [create(c.source), create(other, "other")])
      assert_waiting(c, result, "It was not applied automatically")

      refute translated?(other)
      assert Repo.aggregate(Article, :count) == articles
      assert Repo.aggregate(Oban.Job, :count) == jobs
      assert Translations.alternate_languages(Article, c.source.id) == []
    end

    test "a failure after the copies committed reports what is stored: applied", c do
      grant = allowed!(c)
      result = prepare(c, grant, [create(c.source)])
      assert %{"applied" => true} = result

      # Attempted again, the apply refuses; the proposal is applied all the same
      assert {:applied, %Receipt{id: id}} = AutoApply.run(result["proposal_id"], 1, c.user, grant.id, c.tenant)
      assert id == result["proposal_id"]
      assert %Record{status: "applied", auto_apply_reason: nil} = record(id)
    end

    test "a crash leaves the proposal waiting", c do
      Process.put({:synctest_duplicate, c.source.id}, :raise)
      assert_waiting(c, prepare(c, allowed!(c), [create(c.source)]), "It was not applied automatically")
    end

    test "a copy the content type's own save publishes is rolled back", c do
      Process.put({:synctest_duplicate, c.source.id}, :publish)
      assert_waiting(c, prepare(c, allowed!(c), [create(c.source)]), "would not be an unpublished draft")
      assert Repo.aggregate(from(a in Article, where: a.status == :published and a.language == :en), :count) == 0
    end

    test "a created copy without a status, or with a publication ahead, is not an unpublished draft", c do
      saved = fn entry -> [{{:new, "english"}, entry, nil}] end

      assert_raise Error, ~r/unpublished draft/, fn ->
        AutoApply.unpublished!(saved.(%Brando.AuthorizationTestResources.Snippet{id: 1}))
      end

      ahead = DateTime.add(DateTime.utc_now(), 3600, :second)
      page = Factory.insert(:page, status: :draft, publish_at: ahead, creator: c.user)
      assert_raise Error, ~r/unpublished draft/, fn -> AutoApply.unpublished!(saved.(page)) end

      page = page |> Ecto.Changeset.change(publish_at: nil) |> Repo.update!()
      assert AutoApply.unpublished!(saved.(page)) == :ok
    end

    test "a waiting proposal is not one with problems: the tool's next proposal leaves it alone", c do
      waiting = prepare(c, grant!(c.user, c.tenant), [create(c.source)])
      other = article!(c.user, c.module)
      next = prepare(c, grant!(c.user, c.tenant), [create(other)], %{})

      refute next["replaced"]
      assert %Record{status: "pending"} = record(waiting["proposal_id"])
    end
  end

  describe "who may review" do
    setup c do
      put_test_env(:authorization_mode, :groups)
      Boundary.put_scope(nil)
      owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      {:ok, _} = Migration.run()
      Map.put(c, :scope, Scope.standalone(owner))
    end

    defp member(c, keys) do
      user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      {:ok, group} = Groups.create(c.scope, %{name: "Group #{System.unique_integer([:positive])}"}, keys)
      {:ok, :ok} = Groups.add_member(c.scope, group.id, user.id)
      {enable_two_factor(user), group}
    end

    defp content_keys,
      do: (Catalog.preset_permissions(:editor, :standalone) ++ ["brando.mcp.connect"]) -- ["brando.assistant.use"]

    test "someone who may connect and translate, but not use the Assistant, has it wait", c do
      {user, _group} = member(c, content_keys())
      grant = grant!(user, c.tenant, auto_apply: AutoApply.kind())

      result = prepare(c, grant, [create(c.source)], %{"apply" => "if_allowed"}, user)
      assert_waiting(c, result, "may not review proposals")
    end

    test "losing Assistant → Use after preparing, the apply waits", c do
      {user, _group} = member(c, content_keys())

      {:ok, use_group} =
        Groups.create(c.scope, %{name: "Use #{System.unique_integer([:positive])}"}, ["brando.assistant.use"])

      {:ok, :ok} = Groups.add_member(c.scope, use_group.id, user.id)
      grant = grant!(user, c.tenant, auto_apply: AutoApply.kind())

      {:ok, [op]} = Codec.decode_all([create(c.source)])

      proposal =
        Boundary.with_scope(Scope.standalone(user), fn ->
          {:ok, proposal} = Proposals.propose([op], user, origin: :mcp, client: "Test Client", replaces: :latest)
          proposal
        end)

      {:ok, :ok} = Groups.remove_member(c.scope, use_group.id, user.id)

      assert {:waiting, reason} =
               Boundary.with_scope(Scope.standalone(user), fn ->
                 AutoApply.run(proposal.id, 1, user, grant.id, c.tenant)
               end)

      assert reason =~ "may not review proposals"
      refute translated?(c.source)
    end
  end

  describe "what the tool is told" do
    test "the instructions and the tool's description no longer promise that nothing is saved", c do
      instructions = MCP.Server.instructions(c.tenant, grant!(c.user, c.tenant))
      assert instructions =~ "except one that only creates unpublished translations"

      %{description: description} = Enum.find(Registry.definitions(), &(&1.name == "prepare_proposal"))
      assert description =~ ~s(With "apply":"if_allowed")
      # A retry is a new proposal
      assert description =~ "call list_proposals before you call again"
    end
  end

  describe "where it shows" do
    test "Activity says it was applied automatically, and undo by the person says who undid it", c do
      result = prepare(c, allowed!(c), [create(c.source)])
      id = result["proposal_id"]

      applied = Repo.all(from(e in Event, where: e.proposal_id == ^id, preload: [:approver, :user]))
      assert applied != []
      assert Enum.all?(applied, &(&1.details["auto_applied"] == true))
      assert Enum.all?(applied, &(Events.approver_label(&1) =~ "Applied automatically as #{c.user.name}"))
      refute Enum.any?(applied, &(Events.approver_label(&1) =~ "Approved by"))
      # Made as the connection's person, approved by no one
      assert Enum.all?(applied, &(&1.user_id == c.user.id and is_nil(&1.approver_id)))
      assert Enum.all?(applied, &(Events.proposal_path(&1, Events.viewer(c.user)) == "/admin/assistant/connected/#{id}"))

      grant = Repo.get!(Grant, result |> then(fn _ -> record(id).auto_applied_grant_id end))
      assert [%{changed_by: "connection", applied_automatically: true, status: "applied"}] = listed(c, grant)

      assert {:ok, _} = Proposals.undo(id, c.user)

      undone =
        Repo.all(
          from(e in Event, where: e.proposal_id == ^id and e.id not in ^Enum.map(applied, & &1.id), preload: [:approver])
        )

      assert undone != []
      assert Enum.all?(undone, &(Events.approver_label(&1) =~ "Undone by #{c.user.name}"))
      assert Enum.all?(undone, &(&1.approver_id == c.user.id))
      assert [%{changed_by: "person", applied_automatically: true, status: "undone"}] = listed(c, grant)
    end

    test "the review list keeps every waiting proposal, however many were applied since", c do
      waiting = prepare(c, grant!(c.user, c.tenant), [create(c.source)])
      now = DateTime.utc_now()

      applied =
        for n <- 1..31 do
          %{
            id: Ecto.UUID.generate(),
            version: 1,
            scope: record(waiting["proposal_id"]).scope,
            actor_id: c.user.id,
            origin: "mcp",
            client: "Test Client",
            operations: [],
            fingerprints: %{},
            module_versions: [],
            problems: [],
            effects: %{},
            status: "applied",
            auto_applied_grant_id: 1,
            expires_at: now,
            inserted_at: DateTime.add(now, n, :second),
            updated_at: now
          }
        end

      Repo.insert_all(Record, applied)

      listed = Proposals.list_external(c.user)
      assert waiting["proposal_id"] in Enum.map(listed, & &1.id)
      assert length(listed) == 31
      assert Proposals.count_external(c.user) == 1
    end
  end

  defp listed(c, grant) do
    {:ok, %{proposals: proposals}} =
      Registry.call("list_proposals", %{}, %Registry.Context{actor: c.user, origin: :mcp, client: grant.client_name})

    proposals
  end
end
