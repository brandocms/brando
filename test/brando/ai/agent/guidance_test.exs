defmodule Brando.AI.Agent.GuidanceTest do
  use Brando.ConnCase, async: false

  alias Brando.AI.Agent
  alias Brando.AI.Agent.{Conversation, Guidance, Prompt}
  alias Brando.AI.Agent.Guidance.Version
  alias Brando.Content.Transfer
  alias Brando.{Factory, Repo}

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
end
