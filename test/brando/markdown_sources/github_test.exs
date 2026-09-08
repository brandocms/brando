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

  test "fetches the current ref and immutable ordinary blob through fixed provider URLs", context do
    assert {:ok, %{commit: @commit, markdown: "# Doc"}} = GitHub.fetch(context.connection, context.source)
    assert_received {:github_request, "/repos/acme/docs/git/blobs/" <> @blob}
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
