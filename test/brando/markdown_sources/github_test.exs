defmodule Brando.MarkdownSources.GitHubTest do
  use ExUnit.Case, async: false
  alias Brando.MarkdownSources.GitHub
  @commit String.duplicate("a", 40)
  @tree String.duplicate("b", 40)
  @blob String.duplicate("c", 40)

  defmodule Client do
    def get(path) do
      send(self(), {:github_request, path})
      Map.get(Process.get(:github_responses), path, {:error, :unexpected_url})
    end
  end

  setup do
    old = Application.get_env(:brando, :markdown_sources_http)
    Application.put_env(:brando, :markdown_sources_http, Client)

    on_exit(fn ->
      if old,
        do: Application.put_env(:brando, :markdown_sources_http, old),
        else: Application.delete_env(:brando, :markdown_sources_http)
    end)

    responses = %{
      "/repos/acme/docs" => {:ok, %{"id" => 42, "private" => false}},
      "/repos/acme/docs/git/ref/heads/main" => {:ok, %{"object" => %{"type" => "commit", "sha" => @commit}}},
      "/repos/acme/docs/git/commits/#{@commit}" => {:ok, %{"tree" => %{"sha" => @tree}}},
      "/repos/acme/docs/git/trees/#{@tree}" =>
        {:ok,
         %{
           "truncated" => false,
           "tree" => [%{"path" => "README.md", "type" => "blob", "mode" => "100644", "sha" => @blob}]
         }},
      "/repos/acme/docs/git/blobs/#{@blob}" =>
        {:ok, %{"encoding" => "base64", "size" => 5, "content" => Base.encode64("# Doc")}}
    }

    Process.put(:github_responses, responses)
    {:ok, connection: %{repository: "acme/docs", repository_id: 42}, source: %{path: "README.md", ref: "refs/heads/main"}}
  end

  test "folder discovery includes nested Markdown and rejects incomplete trees", context do
    url = "/repos/acme/docs/git/trees/#{@tree}?recursive=1"

    nodes = [
      %{"path" => "README.md", "type" => "blob", "mode" => "100644"},
      %{"path" => "guides/install.markdown", "type" => "blob", "mode" => "100644"},
      %{"path" => "photo.jpg", "type" => "blob", "mode" => "100644"},
      %{"path" => "symlink.md", "type" => "blob", "mode" => "120000"},
      %{"path" => "../unsafe.md", "type" => "blob", "mode" => "100644"}
    ]

    original = Process.get(:github_responses)
    connection = Map.put(context.connection, :key, "docs")
    Process.put(:github_responses, Map.put(original, url, {:ok, %{"tree" => nodes, "truncated" => false}}))

    assert {:ok, ["README.md", "guides/install.markdown"]} =
             GitHub.list_documents(connection, %{ref: "refs/heads/main", folder: ""})

    assert {:error, _} = GitHub.list_documents(connection, %{ref: "refs/heads/main", folder: "../guides"})
    Process.put(:github_responses, Map.put(original, url, {:ok, %{"tree" => nodes, "truncated" => true}}))
    assert {:error, :too_many_documents} = GitHub.list_documents(connection, %{ref: "refs/heads/main", folder: ""})
  end

  test "fetches the current ref and immutable ordinary blob through fixed provider URLs", context do
    assert {:ok, %{commit: @commit, markdown: "# Doc"}} = GitHub.fetch(context.connection, context.source)
    assert_received {:github_request, "/repos/acme/docs/git/blobs/" <> @blob}
  end

  test "folder discovery scopes the tree to the selected directory", context do
    child = String.duplicate("d", 40)
    directory = %{"path" => "guides", "type" => "tree", "mode" => "040000", "sha" => child}
    original = Process.get(:github_responses)

    responses =
      original
      |> Map.put("/repos/acme/docs/git/trees/#{@tree}", {:ok, %{"tree" => [directory], "truncated" => false}})
      |> Map.put(
        "/repos/acme/docs/git/trees/#{child}?recursive=1",
        {:ok, %{"tree" => [%{"path" => "start.md", "type" => "blob", "mode" => "100644"}], "truncated" => false}}
      )

    Process.put(:github_responses, responses)
    connection = Map.put(context.connection, :key, "docs")

    assert {:ok, ["guides/start.md"]} =
             GitHub.list_documents(connection, %{ref: "refs/heads/main", folder: "guides"})

    refute_received {:github_request, "/repos/acme/docs/git/trees/" <> @tree <> "?recursive=1"}

    symlink = Map.merge(directory, %{"type" => "blob", "mode" => "120000"})

    Process.put(
      :github_responses,
      Map.put(responses, "/repos/acme/docs/git/trees/#{@tree}", {:ok, %{"tree" => [symlink], "truncated" => false}})
    )

    assert {:error, :invalid_folder} = GitHub.list_documents(connection, %{ref: "refs/heads/main", folder: "guides"})
  end

  test "rejects a replaced repository, private content, symlinks and oversized blobs", context do
    original = Process.get(:github_responses)

    for replacement <- [%{"id" => 999, "private" => false}, %{"id" => 42, "private" => true}] do
      Process.put(:github_responses, Map.put(original, "/repos/acme/docs", {:ok, replacement}))
      assert {:error, _} = GitHub.fetch(context.connection, context.source)
    end

    symlink = %{
      "truncated" => false,
      "tree" => [%{"path" => "README.md", "type" => "blob", "mode" => "120000", "sha" => @blob}]
    }

    Process.put(:github_responses, Map.put(original, "/repos/acme/docs/git/trees/#{@tree}", {:ok, symlink}))
    assert {:error, :unsupported_file_type} = GitHub.fetch(context.connection, context.source)

    Process.put(
      :github_responses,
      Map.put(
        original,
        "/repos/acme/docs/git/blobs/#{@blob}",
        {:ok, %{"encoding" => "base64", "size" => 600_000, "content" => ""}}
      )
    )

    assert {:error, :invalid_document} = GitHub.fetch(context.connection, context.source)
  end
end
