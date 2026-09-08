defmodule Brando.MarkdownSources.SyncTest do
  use Brando.ConnCase, async: false
  alias Brando.MarkdownSources
  alias Brando.MarkdownSources.{Connection, Source, Version}
  alias Brando.Villain.Blocks.MarkdownSourceBlock

  defmodule Provider do
    def fetch(_, source) do
      result =
        Process.get(
          :markdown_fetch_result,
          {:ok, %{commit: String.duplicate("a", 40), markdown: "# First", repository: "acme/docs", path: source.path}}
        )

      if is_function(result, 1), do: result.(source), else: result
    end
  end

  setup do
    old = Application.get_env(:brando, :markdown_sources)
    old_provider = Application.get_env(:brando, :markdown_sources_provider)

    Application.put_env(:brando, :markdown_sources,
      connections: %{
        "docs" => %{secret: String.duplicate("s", 40), repository: "acme/docs", repository_id: 42, destinations: [nil]}
      }
    )

    Application.put_env(:brando, :markdown_sources_provider, Provider)

    on_exit(fn ->
      for {key, value} <- [markdown_sources: old, markdown_sources_provider: old_provider] do
        if value, do: Application.put_env(:brando, key, value), else: Application.delete_env(:brando, key)
      end
    end)

    source = Repo.insert!(%Source{name: "Docs", connection: "docs", ref: "refs/heads/main", path: "guides/start.md"})
    {:ok, connection} = Connection.current("docs")
    {:ok, source: source, connection: connection}
  end

  test "disabling a later source does not swallow an earlier source's retryable failure", c do
    other = Repo.insert!(%Source{name: "Other", connection: "docs", ref: c.source.ref, path: "other.md"})

    Process.put(:markdown_fetch_result, fn source ->
      assert source.id == c.source.id
      other |> Source.changeset(%{enabled: false}) |> Repo.update!()
      {:error, :github_timeout}
    end)

    args = %{"connection" => "docs", "ref" => c.source.ref, "generation" => Connection.generation(c.connection)}
    assert {:error, :github_timeout} = Brando.Worker.MarkdownSourceSync.perform(%Oban.Job{args: args})
  end

  test "imports once, follows local versions, and leaves reviewed/pinned content unchanged", %{
    source: source,
    connection: connection
  } do
    assert :ok = Brando.Worker.MarkdownSourceSync.sync(source.id, connection)
    first = MarkdownSources.get_source(source.id).latest_version_id
    assert MarkdownSources.render(%{source_id: source.id, policy: :follow, version_id: nil}) =~ "First"

    Process.put(
      :markdown_fetch_result,
      {:ok, %{commit: String.duplicate("b", 40), markdown: "# Second", repository: "acme/docs", path: source.path}}
    )

    assert :ok = Brando.Worker.MarkdownSourceSync.sync(source.id, connection)
    assert MarkdownSources.render(%{source_id: source.id, policy: :follow, version_id: first}) =~ "Second"

    for policy <- [:review, :pinned],
        do: assert(MarkdownSources.render(%{source_id: source.id, policy: policy, version_id: first}) =~ "First")

    assert :ok = Brando.Worker.MarkdownSourceSync.sync(source.id, connection)
    assert Repo.aggregate(Version, :count) == 2
    assert MarkdownSources.get_source(source.id).publication_sequence == 2
    # A legitimate force push can return to an old immutable version and must
    # have a fresh publication identity rather than being deduplicated forever.
    Process.put(
      :markdown_fetch_result,
      {:ok, %{commit: String.duplicate("a", 40), markdown: "# First", repository: "acme/docs", path: source.path}}
    )

    assert :ok = Brando.Worker.MarkdownSourceSync.sync(source.id, connection)
    assert %{latest_version_id: ^first, publication_sequence: 3} = MarkdownSources.get_source(source.id)
    assert Repo.aggregate(Version, :count) == 2
  end

  test "a provider failure or disabled connection preserves the published version", %{
    source: source,
    connection: connection
  } do
    assert :ok = Brando.Worker.MarkdownSourceSync.sync(source.id, connection)
    first = MarkdownSources.get_source(source.id).latest_version_id
    Process.put(:markdown_fetch_result, {:error, :document_not_found})
    assert {:error, :document_not_found} = Brando.Worker.MarkdownSourceSync.sync(source.id, connection)
    assert %{latest_version_id: ^first, last_error: "document_not_found"} = MarkdownSources.get_source(source.id)
    Application.put_env(:brando, :markdown_sources, connections: %{})
    assert {:cancel, :source_changed} = Brando.Worker.MarkdownSourceSync.sync(source.id, connection)
    assert MarkdownSources.render(%{source_id: source.id, policy: :follow, version_id: nil}) =~ "First"
  end

  test "version IDs cannot reference another document", %{source: source, connection: connection} do
    assert :ok = Brando.Worker.MarkdownSourceSync.sync(source.id, connection)
    version = MarkdownSources.get_source(source.id).latest_version_id
    other = Repo.insert!(%Source{name: "Other", connection: "docs", ref: "refs/heads/main", path: "other.md"})
    assert is_nil(MarkdownSources.get_version(other.id, version))
    assert MarkdownSources.render(%{source_id: other.id, policy: :review, version_id: version}) == ""
  end

  test "module definition updates preserve the placement's source, policy, and accepted version" do
    original = %Brando.Content.Ref{
      data: %MarkdownSourceBlock{data: %MarkdownSourceBlock.Data{source_id: 1, policy: :pinned, version_id: 2}}
    }

    template = %Brando.Content.Ref{data: %MarkdownSourceBlock{data: %MarkdownSourceBlock.Data{}}}

    result =
      MarkdownSourceBlock.apply_ref(MarkdownSourceBlock, template, Ecto.Changeset.change(original))
      |> Ecto.Changeset.apply_changes()

    assert result.data.data == original.data.data
  end

  test "a signed push changes persisted Follow pages while Review pages keep the approved version", %{
    source: source,
    connection: connection
  } do
    assert :ok = Brando.Worker.MarkdownSourceSync.sync(source.id, connection)
    first = MarkdownSources.get_source(source.id).latest_version_id
    user = Brando.Factory.insert(:random_user, role: :superuser)
    Cachex.clear(:query)

    pages =
      for {policy, format} <- [{:follow, :liquid}, {:follow, :heex}, {:review, :liquid}, {:pinned, :heex}] do
        module =
          Brando.Factory.insert(:module,
            type: format,
            code: if(format == :heex, do: "<.ref block={@block} ref={:body} />", else: "{% ref refs.body %}")
          )

        page = Brando.Factory.insert(:page, creator: user)
        join = Brando.Pages.Page.__schema__(:association, :entry_blocks).queryable

        block =
          Repo.insert!(%Brando.Content.Block{
            uid: Brando.Utils.generate_uid(),
            type: :module,
            module_id: module.id,
            source: join,
            creator_id: user.id,
            vars: [],
            refs: [
              %Brando.Content.Ref{
                name: "body",
                uid: Brando.Utils.generate_uid(),
                data: %MarkdownSourceBlock{
                  data: %MarkdownSourceBlock.Data{source_id: source.id, policy: policy, version_id: first}
                }
              }
            ]
          })

        Repo.insert!(struct(join, %{entry_id: page.id, block_id: block.id, sequence: 0}))
        assert {:ok, rendered} = Brando.Content.Blocks.render_entry(Brando.Pages.Page, page.id)
        assert rendered.rendered_blocks =~ "First"
        {:ok, revision} = Brando.Revisions.create_revision(rendered, user)
        {policy, page.id, revision.revision}
      end

    Process.put(
      :markdown_fetch_result,
      {:ok, %{commit: String.duplicate("b", 40), markdown: "# Second", repository: "acme/docs", path: source.path}}
    )

    body = Jason.encode!(%{repository: %{id: 42}, ref: source.ref, after: String.duplicate("b", 40), deleted: false})
    signature = :crypto.mac(:hmac, :sha256, connection.secret, body) |> Base.encode16(case: :lower)

    conn =
      Plug.Test.conn(:post, "https://cms.example.test/api/markdown-sources/webhooks/docs", body)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("x-hub-signature-256", "sha256=" <> signature)
      |> Plug.Conn.put_req_header("x-github-event", "push")
      |> Plug.Conn.put_req_header("x-github-delivery", "integration-1234567890123456")
      |> BrandoWeb.Plugs.GitHubMarkdownWebhook.call([])

    assert conn.status == 202

    for {policy, id, revision} <- pages do
      page = Repo.get!(Brando.Pages.Page, id)
      assert page.status == :published
      assert page.rendered_blocks =~ if(policy == :follow, do: "Second", else: "First")
      assert {:ok, _} = Brando.Revisions.set_entry_to_revision(Brando.Pages.Page, id, revision, user, publish?: true)
      assert {:ok, restored} = Brando.Content.Blocks.render_entry(Brando.Pages.Page, id)
      assert restored.rendered_blocks =~ if(policy == :follow, do: "Second", else: "First")
    end
  end

  test "nested refs refresh fragment consumers without publishing drafts or activating disabled blocks", c do
    assert :ok = Brando.Worker.MarkdownSourceSync.sync(c.source.id, c.connection)
    first = MarkdownSources.get_source(c.source.id).latest_version_id
    user = Brando.Factory.insert(:random_user, role: :superuser)
    module = Brando.Factory.insert(:module, type: :heex, code: "<.ref block={@block} ref={:body} />")
    container = Repo.insert!(%Brando.Content.Container{name: "Documents", namespace: "Test", code: "{{ content }}"})
    fragment = Brando.Factory.insert(:fragment, creator: user)
    fragment_join = Brando.Pages.Fragment.__schema__(:association, :entry_blocks).queryable

    nested = %Brando.Content.Block{
      uid: Brando.Utils.generate_uid(),
      type: :module,
      module_id: module.id,
      source: fragment_join,
      creator_id: user.id,
      vars: [],
      refs: [
        %Brando.Content.Ref{
          name: "body",
          uid: Brando.Utils.generate_uid(),
          data: %MarkdownSourceBlock{
            data: %MarkdownSourceBlock.Data{source_id: c.source.id, policy: :follow, version_id: first}
          }
        }
      ]
    }

    root =
      Repo.insert!(%Brando.Content.Block{
        uid: Brando.Utils.generate_uid(),
        type: :container,
        container_id: container.id,
        source: fragment_join,
        creator_id: user.id,
        children: [nested]
      })

    Repo.insert!(struct(fragment_join, %{entry_id: fragment.id, block_id: root.id, sequence: 0}))
    assert {:ok, rendered} = Brando.Content.Blocks.render_entry(Brando.Pages.Fragment, fragment.id)
    assert rendered.rendered_blocks =~ "First"

    pages =
      for {status, active} <- [{:draft, true}, {:published, false}] do
        page = Brando.Factory.insert(:page, creator: user, status: status)
        join = Brando.Pages.Page.__schema__(:association, :entry_blocks).queryable

        block =
          Repo.insert!(%Brando.Content.Block{
            uid: Brando.Utils.generate_uid(),
            type: :fragment,
            fragment_id: fragment.id,
            source: join,
            creator_id: user.id,
            active: active
          })

        Repo.insert!(struct(join, %{entry_id: page.id, block_id: block.id, sequence: 0}))
        assert {:ok, rendered} = Brando.Content.Blocks.render_entry(Brando.Pages.Page, page.id)
        if active, do: assert(rendered.rendered_blocks =~ "First"), else: refute(rendered.rendered_blocks =~ "First")
        {page.id, block.id, status, active}
      end

    Process.put(
      :markdown_fetch_result,
      {:ok, %{commit: String.duplicate("b", 40), markdown: "# Second", repository: "acme/docs", path: c.source.path}}
    )

    assert :ok = Brando.Worker.MarkdownSourceSync.sync(c.source.id, c.connection)

    for {id, block_id, status, active} <- pages do
      page = Repo.get!(Brando.Pages.Page, id)
      assert page.status == status
      assert Repo.get!(Brando.Content.Block, block_id).active == active
      if active, do: assert(page.rendered_blocks =~ "Second"), else: refute(page.rendered_blocks =~ "Second")
    end
  end
end
