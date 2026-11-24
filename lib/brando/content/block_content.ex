defmodule Brando.Content.BlockContent do
  @moduledoc false

  # The content of a block's refs and vars, set on the block's changeset as
  # the editor sets it: a media ref retyped from its module's template, a
  # gallery made with its first item, a link to an entry through its
  # identifier. Shared by proposals (`Brando.Content.Proposals`) and
  # `Brando.Content.Seed`, which describe a value as:
  #
  #   * media: `{:image, id}`, `{:video, id}`, `{:file, id}`,
  #     `{:gallery, [{:image, id} | {:video, id}]}` for a new gallery, or
  #     `{:gallery, id}` for a saved one
  #   * a var's value: a boolean, one of the media above, a link (a URL,
  #     `{:entry, schema, id}` or `{:link, target, opts}`) or a plain value

  alias Brando.Content
  alias Brando.Content.RefGuard
  alias Ecto.Changeset

  @media_kinds %{image: "picture", video: "video", gallery: "gallery", file: "file"}

  # The media kinds a module ref takes (`Brando.Content.Proposals.accepts/1`)
  def accepts(%{data: %{type: "picture"}}), do: [:image]
  def accepts(%{data: %{type: "video"}}), do: [:video]
  def accepts(%{data: %{type: "file"}}), do: [:file]
  def accepts(%{data: %{type: "gallery"}}), do: [:gallery]

  def accepts(%{data: %{type: "media", data: data}}) do
    available = Map.get(data, :available_blocks) || ["picture", "video"]
    for {kind, type} <- @media_kinds, type in available, do: kind
  end

  def accepts(_), do: []

  # A media slot is retyped from its module definition's template, as the
  # editor's media block does when an editor picks a picture, a video, a
  # gallery or a file.
  def put_media(ref, {kind, value}, module, user) do
    type = Map.fetch!(@media_kinds, kind)
    name = Changeset.get_field(ref, :name)

    ref =
      if Changeset.get_field(ref, :data).type == type do
        ref
      else
        definition = Enum.find(module.refs, &(&1.name == name))

        ref
        |> Changeset.put_change(:data, template(definition, type))
        |> Changeset.put_change(:image_id, nil)
        |> Changeset.put_change(:video_id, nil)
        |> Changeset.put_change(:gallery_id, nil)
        |> Changeset.put_change(:file_id, nil)
      end

    # A list of items makes a new gallery; an id is a saved one, used as is
    if kind == :gallery and is_list(value),
      do: put_gallery(ref, value, "ref:gallery", user),
      else: Changeset.put_change(ref, :"#{kind}_id", value)
  end

  # A gallery's objects are replaced in order; a ref or var without a gallery
  # gets a new one, as the editor does when the first item is picked.
  defp put_gallery(changeset, items, config_target, user) do
    objects =
      items
      |> Enum.with_index()
      |> Enum.map(fn {{kind, id}, sequence} -> %{:"#{kind}_id" => id, sequence: sequence, creator_id: user.id} end)

    case Changeset.get_field(changeset, :gallery) do
      %Brando.Galleries.Gallery{} = gallery ->
        gallery = gallery |> Changeset.change() |> Changeset.put_assoc(:gallery_objects, objects)
        Changeset.put_assoc(changeset, :gallery, gallery)

      _ ->
        Changeset.put_assoc(changeset, :gallery, %{config_target: config_target, gallery_objects: objects})
    end
  end

  # The field a ref's content lives in, by ref type. A ref without one, or
  # whose text is markup (`RefGuard.markup_types/0`), raises: proposals
  # refuse those before this.
  def put_text(ref, text) do
    %{type: type, data: inner} = block = Changeset.get_field(ref, :data)

    key =
      cond do
        type in RefGuard.markup_types() -> nil
        type == "map" -> :embed_url
        is_map_key(inner, :text) -> :text
        true -> nil
      end

    if is_nil(key) do
      raise ArgumentError,
            "the ref #{inspect(Changeset.get_field(ref, :name))} holds no text: give its data fields as a map"
    end

    Changeset.put_change(ref, :data, %{block | data: Map.put(inner, key, text)})
  end

  defp template(%{data: %{type: "media", data: data}}, "picture"),
    do: %Brando.Villain.Blocks.PictureBlock{
      type: "picture",
      data: normalize_caption(data.template_picture || %Brando.Villain.Blocks.PictureBlock.Data{})
    }

  defp template(%{data: %{type: "media", data: data}}, "video"),
    do: %Brando.Villain.Blocks.VideoBlock{
      type: "video",
      data: normalize_caption(data.template_video || %Brando.Villain.Blocks.VideoBlock.Data{})
    }

  defp template(%{data: %{type: "media", data: data}}, "gallery"),
    do: %Brando.Villain.Blocks.GalleryBlock{
      type: "gallery",
      data: data.template_gallery || %Brando.Villain.Blocks.GalleryBlock.Data{}
    }

  defp template(%{data: %{type: "media", data: data}}, "file"),
    do: %Brando.Villain.Blocks.FileBlock{
      type: "file",
      data: data.template_file || %Brando.Villain.Blocks.FileBlock.Data{}
    }

  # A template's caption is rich text, which the module's template doesn't
  # store as a ref does (`Brando.Captions.normalize/1`)
  defp normalize_caption(data), do: %{data | title: Brando.Captions.normalize(data.title)}

  def put_values(block, values, _user) when values == %{}, do: block

  def put_values(block, values, user) do
    vars =
      block
      |> Changeset.get_assoc(:vars)
      |> Enum.map(fn var ->
        case Map.fetch(values, Changeset.get_field(var, :key)) do
          {:ok, value} -> put_value(var, Changeset.get_field(var, :type), value, user)
          :error -> var
        end
      end)

    Changeset.put_assoc(block, :vars, vars)
  end

  defp put_value(var, :boolean, value, _user), do: Changeset.put_change(var, :value_boolean, value)
  defp put_value(var, :gallery, {:gallery, items}, user), do: put_gallery(var, items, "default", user)

  defp put_value(var, kind, {kind, id}, _user) when kind in [:image, :video, :file],
    do: Changeset.put_change(var, :"#{kind}_id", id)

  defp put_value(var, :link, {:link, target, opts}, user) do
    var = if target, do: put_value(var, :link, target, user), else: var
    Changeset.change(var, link_options(opts))
  end

  defp put_value(var, :link, {:entry, schema, id}, _user) do
    {:ok, identifier} = Content.get_identifier(schema, %{id: id})
    Changeset.change(var, link_type: :identifier, identifier_id: identifier.id)
  end

  # A URL link holds no entry, and no link holds neither.
  defp put_value(var, :link, url, _user) when is_binary(url) or is_nil(url),
    do: Changeset.change(var, link_type: :url, value: url, identifier_id: nil)

  defp put_value(var, _type, value, _user), do: Changeset.put_change(var, :value, value)

  # An empty text leaves the link to show its default: an entry's title.
  def link_options(opts) do
    Enum.reduce(opts, %{}, fn
      {:text, text}, acc -> Map.put(acc, :link_text, if(text == "", do: nil, else: text))
      {:new_tab, new_tab}, acc -> Map.put(acc, :link_target_blank, new_tab)
    end)
  end
end
