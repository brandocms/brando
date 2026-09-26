defmodule Brando.Content.Proposals.RefConfig do
  @moduledoc """
  The settings of a ref: the fields of its type's data — a heading's level, a
  picture's alt text and link, a video's autoplay, a gallery's display —
  except its content. Text, code, embed addresses and media have their own
  operations; sizes, paths, dimensions and config targets are the media
  pipeline's.

  Values are cast by the ref type's own embedded schema, so a proposal can
  only set what the editor's ref form could.
  """
  alias Ecto.Changeset

  @content ~w(text code embed_url sizes path width height dominant_color cdn config_target image_config_target
              video_config_target gallery allowed_types footnotes footnote_module_set extensions formats srcset
              media_queries remote_id source thumbnail_url url poster_url file_id image_id video_id)a

  # A media slot can hold any of these, each with its own settings.
  @media_types ~w(picture video gallery)

  @doc "The data schema of ref type `type`, or `nil`."
  @spec data_module(String.t()) :: module() | nil
  def data_module(type) when is_binary(type) do
    with {:ok, block} <- Keyword.fetch(Brando.Villain.Blocks.list_blocks(), String.to_existing_atom(type)),
         data = Module.concat(block, Data),
         true <- Code.ensure_loaded?(data) and function_exported?(data, :__schema__, 1) do
      data
    else
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "The settable fields of ref type `type`."
  @spec keys(String.t()) :: [atom()]
  def keys(type) do
    case data_module(type) do
      nil -> []
      data -> data.__schema__(:fields) -- (data.__schema__(:embeds) ++ data.__schema__(:primary_key) ++ @content)
    end
  end

  @doc """
  The settings of a ref definition, for `describe_module`: each field with
  its type and, for enums, its values. A media slot lists each type it can
  hold.
  """
  @spec describe(map()) :: map() | [map()]
  def describe(%{data: %{type: "media"}}), do: Map.new(@media_types, &{&1, describe_type(&1)})
  def describe(%{data: %{type: type}}), do: describe_type(type)

  defp describe_type(type) do
    data = data_module(type)

    for key <- keys(type) do
      case data.__schema__(:type, key) do
        {:parameterized, {Ecto.Enum, %{mappings: mappings}}} ->
          %{key: key, type: "one of", values: Keyword.keys(mappings)}

        {:array, {:parameterized, {Ecto.Enum, %{mappings: mappings}}}} ->
          %{key: key, type: "list of", values: Keyword.keys(mappings)}

        ecto_type ->
          %{key: key, type: inspect_type(ecto_type)}
      end
    end
  end

  defp inspect_type(type) when is_atom(type), do: to_string(type)
  defp inspect_type(type), do: inspect(type)

  @doc """
  Problems with `config` for the ref `name` of a module definition. A media
  slot accepts settings valid for any type it can hold; they are applied to
  the one it holds.
  """
  @spec problems(String.t(), map(), map()) :: [String.t()]
  def problems(name, %{data: %{type: type}}, config) do
    types = if type == "media", do: @media_types, else: [type]
    results = Enum.map(types, &check(&1, config))

    cond do
      Enum.any?(results, &(&1 == :ok)) -> []
      types == [type] -> [elem(hd(results), 1)]
      true -> ["#{name} has no such settings for the media it can hold."]
    end
  end

  defp check(type, config) do
    keys = keys(type)
    unknown = Map.keys(config) -- Enum.map(keys, &to_string/1)

    cond do
      keys == [] ->
        {:error, "This ref has no settings."}

      unknown != [] ->
        {:error, "Unknown setting #{Enum.join(unknown, ", ")}. Settable: #{Enum.join(keys, ", ")}."}

      true ->
        changeset = Changeset.cast(struct(data_module(type)), config, keys)

        if changeset.valid?,
          do: :ok,
          else:
            {:error,
             "Invalid setting: " <>
               Enum.map_join(changeset.errors, ", ", fn {key, {message, _}} -> "#{key} #{message}" end)}
    end
  end

  @doc "Apply `config` to a ref changeset, cast by the type the ref holds."
  @spec put(Changeset.t(), map()) :: Changeset.t()
  def put(ref, config) when config == %{}, do: ref

  def put(ref, config) do
    %{type: type, data: inner} = block = Changeset.get_field(ref, :data)
    keys = keys(type)
    config = Map.take(config, Enum.map(keys, &to_string/1))
    inner = inner |> Changeset.cast(config, keys) |> Changeset.apply_changes()
    Changeset.put_change(ref, :data, %{block | data: inner})
  end

  @doc "A ref's settings that differ from its type's defaults, for outlines."
  @spec current(map()) :: map()
  def current(%{data: %{type: type, data: inner}}) when is_map(inner) do
    case data_module(type) do
      nil ->
        %{}

      data ->
        defaults = struct(data)

        for key <- keys(type),
            value = Map.get(inner, key),
            value not in [nil, "", []],
            value != Map.get(defaults, key),
            into: %{},
            do: {key, value}
    end
  end

  def current(_), do: %{}

  @doc "The settings `config` would change on a saved ref, as `{key, before, after}`."
  @spec diff(map() | nil, map()) :: [{String.t(), term(), term()}]
  def diff(ref, config) do
    inner = (ref && ref.data && ref.data.data) || %{}
    for {key, value} <- config, do: {key, Map.get(inner, String.to_existing_atom(key)), value}
  rescue
    ArgumentError -> Enum.map(config, fn {key, value} -> {key, nil, value} end)
  end
end
