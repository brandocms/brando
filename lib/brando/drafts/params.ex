defmodule Brando.Drafts.Params do
  @moduledoc "Versionable, JSON-safe editor parameters, including values that failed casting."
  alias Ecto.Changeset

  @ignored ~w(__meta__ __struct__ password password_confirmation password_hash inserted_at updated_at rendered_at)

  def snapshot(%Changeset{} = cs) do
    cs.data
    |> snapshot()
    |> Map.merge(changes(cs))
    |> preserve_invalid(cs)
    |> clean()
  end

  def snapshot(%Ecto.Association.NotLoaded{}), do: nil
  def snapshot(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def snapshot(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def snapshot(%Date{} = value), do: Date.to_iso8601(value)
  def snapshot(%Time{} = value), do: Time.to_iso8601(value)
  def snapshot(%Decimal{} = value), do: Decimal.to_string(value)

  def snapshot(%mod{} = value) do
    if function_exported?(mod, :__schema__, 1) do
      assocs =
        Enum.filter(mod.__schema__(:associations), fn key ->
          assoc = mod.__schema__(:association, key)

          (assoc.cardinality == :many or key == :block or assoc.queryable == Brando.Galleries.Gallery) and
            not is_nil(Map.get(value, key)) and not match?(%Ecto.Association.NotLoaded{}, Map.get(value, key))
        end)

      virtuals = if mod == Brando.Content.Block && value.slot_remap, do: [:slot_remap], else: []
      value |> Map.take(mod.__schema__(:fields) ++ assocs ++ virtuals) |> snapshot()
    else
      value |> Map.from_struct() |> snapshot()
    end
  end

  def snapshot(value) when is_map(value), do: value |> Map.new(fn {k, v} -> {to_string(k), snapshot(v)} end) |> clean()

  def snapshot(value) when is_list(value) do
    value
    |> Enum.reject(&match?(%Changeset{action: action} when action in [:replace, :delete], &1))
    |> Enum.map(&snapshot/1)
  end

  def snapshot(value) when is_atom(value) and value not in [nil, true, false], do: to_string(value)
  def snapshot(value), do: value

  # Library assets already exist before they are selected. Store their FK even
  # when a picker used put_assoc, so recovery never inserts a duplicate asset.
  defp changes(cs) do
    schema = Map.get(cs.data, :__struct__)

    Enum.reduce(cs.changes, %{}, fn {key, value}, params ->
      assoc = if schema && key in schema.__schema__(:associations), do: schema.__schema__(:association, key)

      case assoc do
        %Ecto.Association.BelongsTo{related: related, owner_key: fk}
        when related in [Brando.Images.Image, Brando.Videos.Video, Brando.Files.File] ->
          asset = if match?(%Changeset{}, value), do: Changeset.apply_changes(value), else: value
          Map.put(params, to_string(fk), asset && Map.get(asset, :id))

        _ ->
          Map.put(params, to_string(key), snapshot(value))
      end
    end)
  end

  # Only invalid fields overlay the cast result. Replaying every raw param
  # would resurrect deleted rows and reverse one-shot picker/structural edits.
  def preserve_invalid(params, %Changeset{} = cs) do
    Enum.reduce(cs.errors, params, fn {field, _}, acc ->
      key = to_string(field)
      if cs.params && Map.has_key?(cs.params, key), do: Map.put(acc, key, snapshot(cs.params[key])), else: acc
    end)
  end

  def preserve_invalid_tree(params, %Changeset{} = cs) do
    Enum.reduce(cs.changes, params, fn
      {field, %Changeset{} = child}, acc ->
        Map.update(acc, to_string(field), %{}, &preserve_invalid_tree(&1, child))

      {field, children}, acc when is_list(children) ->
        children = Enum.reject(children, &match?(%Changeset{action: action} when action in [:delete, :replace], &1))

        Map.update(acc, to_string(field), [], fn values ->
          values
          |> Enum.with_index()
          |> Enum.map(fn {value, idx} ->
            case Enum.at(children, idx) do
              %Changeset{} = child -> preserve_invalid_tree(value, child)
              _ -> value
            end
          end)
        end)

      _, acc ->
        acc
    end)
    |> preserve_invalid(cs)
  end

  def clean(params) do
    Map.reject(params, fn {key, _} -> key in @ignored or String.starts_with?(key, ["rendered_", "_unused_", "__"]) end)
  end

  def without_identity(params) when is_map(params) do
    params
    |> Map.drop([
      "id",
      "creator_id",
      "entry_id",
      "parent_id",
      "module_id",
      "block_id",
      "table_row_id",
      "module_version",
      "source"
    ])
    |> Map.new(fn {k, v} -> {k, without_identity(v)} end)
  end

  def without_identity(params) when is_list(params), do: Enum.map(params, &without_identity/1)
  def without_identity(params), do: params

  def merge(left, right) when is_map(left) and is_map(right), do: Map.merge(left, right, fn _, a, b -> merge(a, b) end)

  def merge(left, right) when is_list(left) and is_map(right) do
    if Enum.all?(Map.keys(right), &match?({_, ""}, Integer.parse(&1))) do
      left
      |> Enum.with_index()
      |> Map.new(fn {value, idx} -> {to_string(idx), value} end)
      |> merge(right)
      |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
      |> Enum.map(&elem(&1, 1))
    else
      right
    end
  end

  def merge(_left, right), do: right

  def overlay_block(block, forms) do
    raw = forms[block["uid"]] || %{}
    raw = raw["block"] || raw
    children = Enum.map(block["children"] || [], &overlay_block(&1, forms))

    block
    |> merge(Map.drop(raw, ["children", "sequence", "id", "source", "module_version"]))
    |> Map.put("children", children)
  end
end
