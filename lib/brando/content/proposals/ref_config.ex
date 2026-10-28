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
  alias Brando.Villain.Blocks.HtmlBlock
  alias Ecto.Changeset

  @content ~w(text code embed_url sizes path width height dominant_color cdn config_target image_config_target
              video_config_target gallery allowed_types footnotes footnote_module_set extensions formats srcset
              media_queries remote_id source thumbnail_url url poster_url file_id image_id video_id)a

  # A text or header ref's placeholder is the module's hint for an empty field,
  # set in its definition; it isn't a setting of the block. (On pictures and
  # galleries `placeholder` is a display setting, so it stays there.)
  # An SVG ref's class belongs to its markup, which only a superuser changes.
  @definition_only %{"text" => [:placeholder], "header" => [:placeholder], "svg" => [:class]}

  # A media slot can hold any of these, each with its own settings.
  @media_types ~w(picture video gallery file)

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
      nil ->
        []

      data ->
        data.__schema__(:fields) --
          (data.__schema__(:embeds) ++ data.__schema__(:primary_key) ++ @content ++ Map.get(@definition_only, type, []))
    end
  end

  @doc """
  The settings of a ref definition, for `describe_module`: each field with
  its type and, for enums, its values. A media slot lists each type it can
  hold.
  """
  @spec describe(map()) :: map() | [map()]
  def describe(%{data: %{type: "media"}}), do: Map.new(@media_types, &{&1, describe_type(&1)})

  # An HTML ref's only setting is its parameters' values, by key.
  def describe(%{data: %{type: "html", data: data}}) do
    case HtmlBlock.params_by_key(data || %{}) do
      params when params == %{} ->
        []

      params ->
        [
          %{
            key: :values,
            type: "object of parameter values",
            params: for({key, type} <- params, do: %{key: key, type: to_string(type), takes: takes(type)})
          }
        ]
    end
  end

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

  defp takes(:id), do: "letters, digits, _ and - only"
  defp takes(:number), do: "a number"
  defp takes(:url), do: "an https or relative address"
  defp takes(_text), do: "plain text"

  defp inspect_type(type) when is_atom(type), do: to_string(type)
  defp inspect_type(type), do: inspect(type)

  @doc """
  Problems with `config` for the ref `name` of a module definition. A media
  slot accepts settings valid for any type it can hold; they are applied to
  the one it holds.
  """
  @spec problems(String.t(), map(), map()) :: [String.t()]
  def problems(name, %{data: %{type: "html", data: data}}, config) do
    params = HtmlBlock.params_by_key(data || %{})
    unknown = Map.keys(config) -- ["values"]

    cond do
      params == %{} ->
        ["This ref has no settings."]

      unknown != [] ->
        ["Unknown setting #{Enum.join(unknown, ", ")}. Settable: values."]

      not is_map(config["values"]) ->
        ["#{name} takes values as an object of parameter values."]

      true ->
        for {key, value} <- config["values"], problem = value_problem(params, to_string(key), value), do: problem
    end
  end

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

  defp value_problem(params, key, value) do
    case params do
      %{^key => type} ->
        unless (is_binary(value) or is_number(value)) and HtmlBlock.valid_value?(type, value),
          do: "#{key} takes #{takes(type)}."

      _ ->
        "There is no parameter #{key}. Parameters: #{params |> Map.keys() |> Enum.join(", ")}."
    end
  end

  @doc "Apply `config` to a ref changeset, cast by the type the ref holds."
  @spec put(Changeset.t(), map()) :: Changeset.t()
  def put(ref, config) when config == %{}, do: ref

  # The values of the ref's own parameters that are valid for their type;
  # the template and the parameters stay as they are.
  def put(ref, %{"values" => values}) when is_map(values) do
    case Changeset.get_field(ref, :data) do
      %{type: "html", data: inner} = block ->
        params = HtmlBlock.params_by_key(inner)

        values =
          for {key, value} <- HtmlBlock.normalize_values(values),
              type = params[key],
              type != nil and HtmlBlock.valid_value?(type, value),
              into: inner.values || %{},
              do: {key, value}

        Changeset.put_change(ref, :data, %{block | data: %{inner | values: values}})

      _ ->
        ref
    end
  end

  def put(ref, config) do
    %{type: type, data: inner} = block = Changeset.get_field(ref, :data)
    # An HTML ref's values go through the clause above, checked, or not at all
    keys = if type == "html", do: [], else: keys(type)
    config = Map.take(config, Enum.map(keys, &to_string/1))
    inner = inner |> Changeset.cast(config, keys) |> normalize_caption(type) |> Changeset.apply_changes()
    Changeset.put_change(ref, :data, %{block | data: inner})
  end

  # A picture's or video's caption is rich text, stored as the block
  # changeset stores it (`Brando.Captions.normalize/1`)
  defp normalize_caption(changeset, type) when type in ~w(picture video),
    do: Changeset.update_change(changeset, :title, &Brando.Captions.normalize/1)

  defp normalize_caption(changeset, _type), do: changeset

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
