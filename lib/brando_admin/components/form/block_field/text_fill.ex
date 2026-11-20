defmodule BrandoAdmin.Components.Form.BlockField.TextFill do
  @moduledoc """
  Reads and writes one text of a block by the path a synchronized
  translation's work item gives it below the block
  (`Brando.Translations.Labels.target/2`): `["refs", name, "text"]`,
  `["vars", key, "value"]`, `["rows", row, "vars", key, "value"]` and the
  others `Brando.Translations.Sync` flattens as text.

  `read/2` reads the block as the editor has it (a struct, applied from the
  op store); `put/4` writes the text into the block's full params
  (`BlockField.Ops.snapshot_params/1`), whose lists are in the struct's
  order, so the BlockField can cast them and send the change as a field op.

  A gallery's per-image texts are not read or written here: they are
  translated in the block.
  """
  alias Brando.Content.Block
  alias Brando.Translations.Sync
  alias Brando.Villain.Blocks.HtmlBlock
  alias Brando.Villain.Blocks.PictureBlock
  alias Brando.Villain.Blocks.VideoBlock

  @text_wrappers Brando.AI.Translation.text_ref_wrapper_types()

  @doc "The block with `uid` in a block tree (its children at any depth), or nil."
  def find_block(%Block{uid: uid} = block, uid), do: block

  def find_block(%Block{children: children}, uid) when is_list(children),
    do: Enum.find_value(children, &find_block(&1, uid))

  def find_block(_block, _uid), do: nil

  @doc "Updates the params of the block with `uid` in a tree of block params."
  def update_block_params(%{"uid" => uid} = params, uid, fun), do: fun.(params)

  def update_block_params(%{"children" => children} = params, uid, fun) when is_list(children),
    do: %{params | "children" => Enum.map(children, &update_block_params(&1, uid, fun))}

  def update_block_params(params, _uid, _fun), do: params

  @doc "The text at `path` in `block`: `{:ok, text}`, or `:error` for a path it has no text at."
  def read(%Block{} = block, path) do
    case locate(block, path) do
      {:ok, _params_path, value} -> {:ok, value}
      :error -> :error
    end
  end

  @doc """
  Puts `text` at `path` into `params`, the full params of `block`.
  Returns `{:ok, params}`, or `:error` for a path it cannot write.
  """
  def put(params, %Block{} = block, path, text) when is_map(params) do
    case locate(block, path) do
      {:ok, params_path, _value} -> put_params(params, params_path, text)
      :error -> :error
    end
  end

  # Where the text is: its value, and the path to it in the block's params
  # (map keys and list indexes)
  defp locate(block, ["refs", name, field]) do
    with {:ok, index, ref} <- find(block.refs, &(&1.name == name)),
         {:ok, inner_path, value} <- ref_text(ref.data, field) do
      {:ok, ["refs", index, "data", "data" | inner_path], value}
    end
  end

  defp locate(block, ["refs", name, "values", key]) do
    with {:ok, index, %{data: %HtmlBlock{data: data}}} <- find(block.refs, &(&1.name == name)),
         :text <- HtmlBlock.params_by_key(data)[key] do
      {:ok, ["refs", index, "data", "data", "values", key], Map.get(data.values || %{}, key)}
    else
      _ -> :error
    end
  end

  defp locate(block, ["vars", key, field]), do: var_text(block.vars, ["vars"], key, field)

  defp locate(block, ["rows", row, "vars", key, field]) do
    rows = loaded(block.table_rows)

    case Enum.find_index(Sync.row_identities(rows) |> Enum.map(&elem(&1, 1)), &(&1 == row)) do
      nil -> :error
      index -> var_text(Enum.at(rows, index).vars, ["table_rows", index, "vars"], key, field)
    end
  end

  defp locate(block, ["identifier_metas", identifier, field]) do
    case block.identifier_metas do
      %{^identifier => %{^field => value}} -> {:ok, ["identifier_metas", identifier, field], value}
      _ -> :error
    end
  end

  defp locate(_block, _path), do: :error

  defp ref_text(%wrapper{data: data}, "text") when wrapper in @text_wrappers, do: {:ok, ["text"], Map.get(data, :text)}

  defp ref_text(%PictureBlock{data: data}, field) when field in ~w(title credits alt),
    do: {:ok, [field], Map.get(data, String.to_existing_atom(field))}

  defp ref_text(%VideoBlock{data: data}, "title"), do: {:ok, ["title"], data.title}
  defp ref_text(_data, _field), do: :error

  # A var's text: its value (a URL's too), or a link's text
  defp var_text(vars, prefix, key, field) do
    attribute =
      case field do
        field when field in ["value", "url"] -> {:value, "value"}
        "link_text" -> {:link_text, "link_text"}
        _ -> nil
      end

    with {name, param} <- attribute,
         {:ok, index, var} <- find(vars, &(&1.key == key)) do
      {:ok, prefix ++ [index, param], Map.get(var, name)}
    else
      _ -> :error
    end
  end

  defp find(list, fun) do
    list = loaded(list)

    case Enum.find_index(list, fun) do
      nil -> :error
      index -> {:ok, index, Enum.at(list, index)}
    end
  end

  defp loaded(list) when is_list(list), do: list
  defp loaded(_), do: []

  defp put_params(params, [key], value) when is_binary(key), do: {:ok, Map.put(params || %{}, key, value)}

  defp put_params(%{} = params, [key | rest], value) when is_binary(key) do
    with {:ok, inner} <- put_params(Map.get(params, key), rest, value), do: {:ok, Map.put(params, key, inner)}
  end

  defp put_params(list, [index | rest], value) when is_list(list) and is_integer(index) do
    with %{} = item <- Enum.at(list, index),
         {:ok, inner} <- put_params(item, rest, value) do
      {:ok, List.replace_at(list, index, inner)}
    else
      _ -> :error
    end
  end

  defp put_params(_params, _path, _value), do: :error
end
