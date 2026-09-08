defmodule Brando.MarkdownSources.AuthorizationTest do
  use Brando.ConnCase, async: false
  alias Brando.MarkdownSources
  alias Brando.MarkdownSources.{Source, Version}
  alias Brando.Villain.Blocks.MarkdownSourceBlock
  alias Brando.Authorization.{Groups, Migration, Scope}

  setup do
    put_test_env(:tenancy_mode, :none)
    put_test_env(:authorization_mode, :legacy)

    put_test_env(:markdown_sources,
      connections: %{
        "docs" => %{repository: "acme/docs", repository_id: 42, secret: String.duplicate("s", 40), destinations: [nil]}
      }
    )

    source = Repo.insert!(%Source{name: "Docs", connection: "docs", ref: "refs/heads/main", path: "start.md"})

    version =
      Repo.insert!(%Version{
        source_id: source.id,
        commit: String.duplicate("a", 40),
        markdown: "first",
        html: "<p>first</p>",
        content_hash: "first",
        repository: "acme/docs",
        path: source.path
      })

    ref = %Brando.Content.Ref{
      data: %MarkdownSourceBlock{
        data: %MarkdownSourceBlock.Data{source_id: source.id, policy: :review, version_id: version.id}
      }
    }

    user = Brando.Factory.insert(:random_user, role: :user)
    owner = Brando.Factory.insert(:random_user, role: :superuser)
    %{source: source, ref: ref, user: user, owner: owner}
  end

  defp change(ref, attrs, user) do
    Brando.Content.Block.ref_changeset(ref, %{data: %{type: "markdown_source", data: attrs}}, user)
  end

  test "a stale account cannot grant itself automatic publishing or detach published content", c do
    refute change(c.ref, %{policy: "follow"}, c.user).valid?
    refute change(c.ref, %{source_id: nil}, c.user).valid?
    assert change(c.ref, %{policy: "follow"}, c.owner).valid?
    Repo.update!(Ecto.Changeset.change(c.owner, active: false))
    refute change(c.ref, %{policy: "follow"}, c.owner).valid?
  end

  test "group publishing grants are independent of entry editing and source management", c do
    put_test_env(:authorization_mode, :groups)
    assert {:ok, _} = Migration.run()
    scope = Scope.standalone(c.owner)

    {:ok, group} =
      Groups.create(
        scope,
        %{name: "Document publishers"},
        ~w(brando.admin.access brando.markdown_sources.read brando.markdown_sources.publish)
      )

    {:ok, :ok} = Groups.add_member(scope, group.id, c.user.id)
    assert change(c.ref, %{policy: "follow"}, c.user).valid?
    assert {:error, :forbidden} = MarkdownSources.refresh(c.source.id, c.user)
    assert {:error, :forbidden} = MarkdownSources.save_source(c.source, %{name: "Hijacked"}, c.user)
    {:ok, :ok} = Groups.remove_member(scope, group.id, c.user.id)
    refute change(c.ref, %{policy: "follow"}, c.user).valid?
  end

  test "an editor can keep existing connections but cannot invent or cross-reference a version", c do
    editor = Brando.Factory.insert(:random_user, role: :editor)
    assert change(c.ref, %{}, c.user).valid?
    refute change(c.ref, %{version_id: 999_999}, editor).valid?
    other = Repo.insert!(%Source{name: "Other", connection: "docs", ref: "refs/heads/main", path: "other.md"})
    refute change(c.ref, %{source_id: other.id}, editor).valid?
    assert {:error, :forbidden} = MarkdownSources.refresh(c.source.id, editor)
  end
end
