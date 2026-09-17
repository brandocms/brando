defmodule Brando.MarkdownSources.GitHub do
  @moduledoc "Fetches ordinary files from a verified public repository at an immutable commit."
  @callback fetch(map(), map()) :: {:ok, map()} | {:error, atom()}

  def fetch(connection, source) do
    client = Application.get_env(:brando, :markdown_sources_http, Brando.MarkdownSources.HTTP)
    base = "/repos/" <> connection.repository
    branch = String.replace_prefix(source.ref, "refs/", "")

    with true <- Brando.MarkdownSources.Source.valid_path?(source.path),
         {:ok, %{"id" => id, "private" => false}} when id == connection.repository_id <- client.get(base),
         {:ok, %{"object" => %{"type" => "commit", "sha" => commit}}} <-
           client.get(base <> "/git/ref/" <> encode_path(branch)),
         true <- sha?(commit),
         {:ok, %{"tree" => %{"sha" => tree}}} <- client.get(base <> "/git/commits/" <> commit),
         {:ok, blob} <- find_blob(client, base, tree, String.split(source.path, "/")),
         {:ok, %{"encoding" => "base64", "content" => content, "size" => size}} when size <= 512_000 <-
           client.get(base <> "/git/blobs/" <> blob),
         {:ok, markdown} <- Base.decode64(content, ignore: :whitespace),
         true <- byte_size(markdown) <= 512_000 and String.valid?(markdown) and not String.contains?(markdown, <<0>>) do
      {:ok, %{commit: commit, markdown: markdown, repository: connection.repository, path: source.path}}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :invalid_document}
    end
  end

  @doc "Lists ordinary Markdown files in a folder, including subfolders, at one verified commit."
  def list_documents(connection, %{ref: ref, folder: folder}) do
    client = Application.get_env(:brando, :markdown_sources_http, Brando.MarkdownSources.HTTP)
    base = "/repos/" <> connection.repository
    branch = String.replace_prefix(ref, "refs/", "")
    folder = String.trim(folder, "/")

    with true <- valid_folder?(folder),
         true <-
           Brando.MarkdownSources.Source.changeset(%Brando.MarkdownSources.Source{}, %{
             name: "Folder",
             connection: connection.key,
             ref: ref,
             path: "README.md"
           }).valid?,
         {:ok, %{"id" => id, "private" => false}} when id == connection.repository_id <- client.get(base),
         {:ok, %{"object" => %{"type" => "commit", "sha" => commit}}} <-
           client.get(base <> "/git/ref/" <> encode_path(branch)),
         true <- sha?(commit),
         {:ok, %{"tree" => %{"sha" => tree}}} <- client.get(base <> "/git/commits/" <> commit),
         {:ok, tree} <- folder_tree(client, base, tree, if(folder == "", do: [], else: String.split(folder, "/"))),
         {:ok, %{"tree" => nodes, "truncated" => false}} when is_list(nodes) <-
           client.get(base <> "/git/trees/" <> tree <> "?recursive=1") do
      paths =
        nodes
        |> Enum.filter(&(&1["type"] == "blob" && &1["mode"] in ["100644", "100755"]))
        |> Enum.map(fn node -> if folder == "", do: node["path"], else: folder <> "/" <> node["path"] end)
        |> Enum.filter(&Brando.MarkdownSources.Source.valid_path?/1)
        |> Enum.uniq()
        |> Enum.sort()

      if length(paths) <= 200, do: {:ok, paths}, else: {:error, :too_many_documents}
    else
      {:ok, %{"truncated" => true}} -> {:error, :too_many_documents}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_folder}
    end
  end

  defp valid_folder?(""), do: true

  defp valid_folder?(folder),
    do: byte_size(folder) <= 480 && Brando.MarkdownSources.Source.valid_path?(folder <> "/file.md")

  defp folder_tree(_, _, tree, []) do
    if sha?(tree), do: {:ok, tree}, else: {:error, :invalid_folder}
  end

  defp folder_tree(_, _, _, parts) when length(parts) > 32, do: {:error, :invalid_folder}

  defp folder_tree(client, base, tree, [part | rest]) do
    with true <- sha?(tree),
         {:ok, %{"tree" => nodes, "truncated" => false}} <- client.get(base <> "/git/trees/" <> tree),
         %{"type" => "tree", "mode" => "040000", "sha" => child} <- Enum.find(nodes, &(&1["path"] == part)) do
      folder_tree(client, base, child, rest)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_folder}
    end
  end

  defp find_blob(_, _, _, parts) when length(parts) > 32, do: {:error, :invalid_path}

  defp find_blob(client, base, tree, [part | rest]) do
    with true <- sha?(tree),
         {:ok, %{"tree" => nodes, "truncated" => false}} when is_list(nodes) <- client.get(base <> "/git/trees/" <> tree),
         node when not is_nil(node) <- Enum.find(nodes, &(&1["path"] == part)),
         true <- sha?(node["sha"]) do
      case {rest, node["type"], node["mode"]} do
        {[], "blob", mode} when mode in ["100644", "100755"] -> {:ok, node["sha"]}
        {[_ | _], "tree", "040000"} -> find_blob(client, base, node["sha"], rest)
        _ -> {:error, :unsupported_file_type}
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :document_not_found}
    end
  end

  defp sha?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{40}\z/, value)

  defp encode_path(path),
    do: path |> String.split("/") |> Enum.map_join("/", &URI.encode(&1, fn c -> URI.char_unreserved?(c) end))
end
