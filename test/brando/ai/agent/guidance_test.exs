defmodule Brando.AI.Agent.GuidanceTest do
  use Brando.ConnCase, async: false

  alias Brando.AI.Agent
  alias Brando.AI.Agent.{Conversation, Guidance, Prompt}
  alias Brando.AI.Agent.Guidance.Version
  alias Brando.Authorization.{Boundary, Catalog, Groups, Migration, Scope}
  alias Brando.Content.Transfer
  alias Brando.{Factory, Repo, Tenant}

  setup do
    previous = Application.get_env(:brando, Agent)
    Application.put_env(:brando, Agent, [])

    on_exit(fn ->
      if previous, do: Application.put_env(:brando, Agent, previous), else: Application.delete_env(:brando, Agent)
    end)

    %{superuser: Factory.insert(:random_user, role: :superuser), admin: Factory.insert(:random_user, role: :admin)}
  end

  defp other_scope!(attrs) do
    Repo.insert!(struct(Version, Map.merge(%{scope: "elsewhere", text: "Elsewhere guidance"}, attrs)))
  end

  describe "who may configure it" do
    test "only superusers without groups authorization", c do
      assert Guidance.configurable?(c.superuser)
      refute Guidance.configurable?(c.admin)
      assert {:error, message} = Guidance.save("Use the lede", c.admin)
      assert message =~ "permission"
      assert {:error, _} = Guidance.history(c.admin)
      assert Guidance.sources(c.admin) == []
    end

    test "groups need the configure capability, which the use capability does not give", c do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      alias Brando.Authorization.{Catalog, Groups, Scope}
      editor = Factory.insert(:random_user, role: :user)
      scope = Scope.standalone(c.superuser)

      {:ok, users} =
        Groups.create(scope, %{name: "Assistant users"}, [
          Catalog.get(:access, :backend).key,
          Catalog.get(:use, :assistant).key
        ])

      {:ok, :ok} = Groups.add_member(scope, users.id, editor.id)
      refute Guidance.configurable?(editor)

      {:ok, configurers} = Groups.create(scope, %{name: "Assistant setup"}, [Catalog.get(:configure, :assistant).key])
      {:ok, :ok} = Groups.add_member(scope, configurers.id, editor.id)
      assert Guidance.configurable?(editor)
    end
  end

  test "every save is a version, and the latest is in use", c do
    assert Guidance.current() == nil
    assert {:ok, first} = Guidance.save("  Start articles with the lede.\r\n", c.superuser)
    assert first.text == "Start articles with the lede."
    assert first.scope == Transfer.scope()
    assert first.author_id == c.superuser.id

    # Saving the same text adds nothing.
    assert {:ok, same} = Guidance.save("Start articles with the lede.", c.superuser)
    assert same.id == first.id

    assert {:ok, second} = Guidance.save("Use two images for portraits.", c.superuser, note: "Copied from Acme")
    assert Guidance.current().id == second.id

    assert {:ok, [newest, oldest]} = Guidance.history(c.superuser)
    assert {newest.id, newest.note, newest.author.id} == {second.id, "Copied from Acme", c.superuser.id}
    assert oldest.id == first.id

    # Clearing is a version too.
    assert {:ok, %{text: ""}} = Guidance.save("", c.superuser)
    assert {:error, message} = Guidance.save(String.duplicate("a", 12_001), c.superuser)
    assert message =~ "12000"
  end

  test "the prompt holds the developers' guidance, then this site's, and says which applies", c do
    Application.put_env(:brando, Agent, guidance: "Developers: use the Text module for text.")
    {:ok, _} = Guidance.save("Administrators: use the Lede module for introductions.", c.superuser)
    other_scope!(%{text: "Another site's convention."})

    conversation = %Conversation{language: "en", scope: Transfer.scope()}

    assert [%{source: :code}, %{source: :admin, text: "Administrators: use the Lede module for introductions."}] =
             Guidance.for_conversation(conversation)

    prompt = Prompt.system(conversation)
    assert prompt =~ ~s(<site_guidance from="developers">\nDevelopers: use the Text module)
    assert prompt =~ ~s(<site_guidance from="administrators">\nAdministrators: use the Lede module)
    assert prompt =~ "the administrators' applies"
    refute prompt =~ "Another site's convention."

    # Cleared guidance is left out.
    {:ok, _} = Guidance.save("", c.superuser)
    assert [%{source: :code}] = Guidance.for_conversation(conversation)
  end

  describe "the guidance for building from Figma" do
    test "is versioned apart from the assistant's, and never reaches the assistant's prompt", c do
      put_test_env(Brando.Figma, guidance: "Developers: header and footer are page chrome.")
      {:ok, assistant} = Guidance.save("Use the lede.", c.superuser)
      {:ok, figma} = Guidance.save("The top text is heading and intro.", c.superuser, kind: :figma)
      {:ok, _} = Guidance.save("The top text is the heading and intro fields.", c.superuser, kind: :figma)

      assert Guidance.current().id == assistant.id
      assert Guidance.current(:figma).text == "The top text is the heading and intro fields."
      assert {:ok, [_newest, %{id: oldest}]} = Guidance.history(c.superuser, kind: :figma)
      assert oldest == figma.id
      assert {:ok, [%{id: only}]} = Guidance.history(c.superuser)
      assert only == assistant.id

      # Not offered to copy as the assistant's guidance elsewhere
      assert Guidance.sources(c.superuser) == []

      conversation = %Conversation{language: "en", scope: Transfer.scope()}
      assert [%{source: :admin, text: "Use the lede."}] = Guidance.for_conversation(conversation)
      prompt = Prompt.system(conversation)
      refute prompt =~ "heading and intro"
      refute prompt =~ "page chrome"

      assert [
               %{source: :code, text: "Developers: header and footer are page chrome."},
               %{source: :admin, text: "The top text is the heading and intro fields."}
             ] = Guidance.for_tool(:figma)

      assert Guidance.code_figma_guidance() == "Developers: header and footer are page chrome."
    end

    test "takes the same right as the assistant's", c do
      assert {:error, message} = Guidance.save("Skip the footer.", c.admin, kind: :figma)
      assert message =~ "permission"
      assert {:error, _} = Guidance.history(c.admin, kind: :figma)
      assert Guidance.current(:figma) == nil
    end
  end

  test "fit cuts the developers' part first, by characters or encoded bytes" do
    parts = [%{source: :code, text: "dddd"}, %{source: :admin, text: "aaaa"}]
    assert [%{source: :code, text: "dd"}, %{source: :admin, text: "aaaa"}] = Guidance.fit(parts, 6, :characters)
    assert [%{source: :admin, text: "aa"}] = Guidance.fit(parts, 2, :characters)
    assert [%{source: :admin, text: "øø"}] = Guidance.fit([%{source: :admin, text: "øøø"}], 5, :json)
    # A quote is two bytes in JSON, a control character six
    assert [%{source: :admin, text: ~s("")}] = Guidance.fit([%{source: :admin, text: ~s("""")}], 5, :json)
    assert [%{source: :admin, text: <<1>>}] = Guidance.fit([%{source: :admin, text: <<1, 1>>}], 11, :json)
  end

  describe "put_tool_result/4" do
    @about "What this guidance is."
    # A result of about 11 KB, as a content type with many fields gives
    @result %{fields: for(i <- 1..100, do: %{name: "field_#{i}", type: "string", description: String.duplicate("x", 60)})}

    for {name, text} <- [
          bullets: String.duplicate("- Use the Lede module first.\n", 400) |> String.slice(0, 12_000),
          quotes: String.duplicate(~s("), 12_000),
          backslashes: String.duplicate("\\", 12_000),
          newlines_and_tabs: String.duplicate("a\n\t", 4_000),
          multibyte: String.duplicate("見出し「」", 2_400)
        ] do
      test "cuts guidance to what fits once encoded (#{name})" do
        text = unquote(text)
        assert byte_size(Jason.encode!(@result)) in 10_000..12_000

        result = Guidance.put_tool_result(@result, [%{source: :admin, text: text}], @about, 24_000)

        assert byte_size(Jason.encode!(result)) <= 24_000
        assert %{guidance: %{about: @about, administrators: administrators}} = result
        assert String.starts_with?(text, administrators)
        # All of it, or as much as fits: one more character would not
        assert administrators == text or byte_size(Jason.encode!(result)) > 24_000 - 8
      end
    end

    test "cuts the developers' part first" do
      parts = [
        %{source: :code, text: String.duplicate("d\n", 2_000)},
        %{source: :admin, text: String.duplicate(~s("), 5_000)}
      ]

      result = Guidance.put_tool_result(@result, parts, @about, 24_000)

      assert byte_size(Jason.encode!(result)) <= 24_000
      assert result.guidance.administrators == String.duplicate(~s("), 5_000)
      assert String.length(result.guidance.developers) < 4_000
    end

    test "leaves the guidance out when none fits, and adds nothing for none" do
      parts = [%{source: :admin, text: "Use the Lede module."}]
      assert Guidance.put_tool_result(@result, parts, @about, byte_size(Jason.encode!(@result)) + 10) == @result
      assert Guidance.put_tool_result(@result, [], @about, 24_000) == @result

      assert %{guidance: %{administrators: "Use the Lede module."}} =
               Guidance.put_tool_result(@result, parts, @about, 24_000)
    end
  end

  test "guidance from other sites and environments can be copied", c do
    {:ok, _} = Guidance.save("Here", c.superuser)

    staging =
      other_scope!(%{scope: "staging", prefix: "tenant_acme_staging", site_key: "acme", environment_key: "staging"})

    # Only the latest version of a scope counts, and a cleared one is not offered.
    other_scope!(%{scope: "cleared", site_key: "beta", environment_key: "production", text: "Old"})
    Process.sleep(2)
    other_scope!(%{scope: "cleared", site_key: "beta", environment_key: "production", text: ""})

    assert [%{id: id, label: "acme / staging", text: "Elsewhere guidance"}] = Guidance.sources(c.superuser)
    assert id == staging.id
    assert {:ok, %{text: "Elsewhere guidance"}} = Guidance.source(staging.id, c.superuser)
    assert {:error, _} = Guidance.source(staging.id, c.admin)
    assert {:error, _} = Guidance.source(Ecto.UUID.generate(), c.superuser)
  end

  describe "guidance from another site, on a screen pinned to this one" do
    setup do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :multi)
      Tenant.put_prefix(nil)
      Boundary.put_scope(nil)

      on_exit(fn ->
        Tenant.put_prefix(nil)
        Boundary.put_scope(nil)
        Tenant.Cache.clear()
      end)

      owner = Factory.insert(:random_user, role: :superuser)
      user = Factory.insert(:random_user, role: :editor)
      alpha = guidance_site("guidance-alpha")
      beta = guidance_site("guidance-beta")
      {:ok, _} = Migration.run()

      permissions = ["brando.admin.access", Catalog.get(:configure, :assistant).key]
      alpha_scope = Scope.site(owner, alpha.site, alpha.environment)
      {:ok, group} = Groups.create(alpha_scope, %{name: "Alpha setup"}, permissions)
      {:ok, :ok} = Groups.add_member(alpha_scope, group.id, user.id)

      version = fn site, text ->
        prefix = Tenant.prefix(site.site, site.environment)

        other_scope!(%{
          scope: "#{site.site.key}/#{site.environment.key}",
          prefix: prefix,
          site_key: site.site.key,
          environment_key: site.environment.key,
          text: text
        })
      end

      %{user: user, owner: owner, alpha: alpha, beta: beta, version: version}
    end

    defp guidance_site(key) do
      {:ok, site} =
        Tenant.Registry.create_site(%{
          name: key,
          key: key,
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      {:ok, environment} = Tenant.Registry.create_environment(site, %{name: "production", key: "production", live: true})

      Ecto.Adapters.SQL.query!(
        Brando.RuntimeConfig.get(:repo_module),
        ~s(CREATE SCHEMA "#{Tenant.prefix(site, environment)}")
      )

      %{site: site, environment: environment}
    end

    defp pinned(user, %{site: site, environment: environment}, fun) do
      scope = Scope.site(user, site, environment)
      Tenant.with_prefix(scope.prefix, fn -> Boundary.with_scope(scope, fun) end)
    end

    test "is not offered to a manager of this site alone", c do
      beta = c.version.(c.beta, "Beta's own conventions")

      pinned(c.user, c.alpha, fn ->
        assert Guidance.configurable?(c.user)
        assert Guidance.sources(c.user) == []
        assert {:error, _} = Guidance.source(beta.id, c.user)
      end)
    end

    test "is offered to whoever may configure that site too", c do
      {:ok, group} =
        Groups.create(Scope.site(c.owner, c.beta.site, c.beta.environment), %{name: "Beta setup"}, [
          "brando.admin.access",
          Catalog.get(:configure, :assistant).key
        ])

      {:ok, :ok} = Groups.add_member(Scope.site(c.owner, c.beta.site, c.beta.environment), group.id, c.user.id)
      beta = c.version.(c.beta, "Beta's own conventions")

      pinned(c.user, c.alpha, fn ->
        assert [%{id: id, text: "Beta's own conventions"}] = Guidance.sources(c.user)
        assert id == beta.id
      end)

      pinned(c.owner, c.alpha, fn ->
        assert Enum.map(Guidance.sources(c.owner), & &1.id) == [beta.id]
      end)
    end
  end
end
