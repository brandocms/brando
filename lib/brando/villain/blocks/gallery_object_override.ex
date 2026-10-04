defmodule Brando.Villain.Blocks.GalleryObjectOverride do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Villain",
    schema: "GalleryObjectOverride",
    singular: "gallery_object_override",
    plural: "gallery_object_overrides",
    gettext_module: Brando.Gettext

  @primary_key false
  data_layer :embedded
  identifier false
  persist_identifier false

  attributes do
    attribute :object_id, :string, required: true
    attribute :object_type, :enum, values: [:image, :video], required: true
    attribute :title, :string
    attribute :credits, :string
    attribute :alt, :string
    # A video's caption for this placement (rich text). An image's caption is
    # its `title`; a video's `title` stays plain, it names the player.
    attribute :caption, :string
    attribute :use_default_title, :boolean, default: true
    attribute :use_default_credits, :boolean, default: true
    attribute :use_default_alt, :boolean, default: true
    attribute :use_default_caption, :boolean, default: true

    # Video playback config overrides
    attribute :autoplay, :boolean
    attribute :loop, :boolean
    attribute :muted, :boolean
    attribute :controls, :boolean
    attribute :preload, :boolean
    attribute :use_default_autoplay, :boolean, default: true
    attribute :use_default_loop, :boolean, default: true
    attribute :use_default_muted, :boolean, default: true
    attribute :use_default_controls, :boolean, default: true
    attribute :use_default_preload, :boolean, default: true
  end

  # `object_id` is the id of the image or video, and images and videos are
  # numbered by separate sequences — image 45 and video 45 can sit in the same
  # gallery. An override therefore only identifies its media together with
  # `object_type`. An override stored without a type matches on the id alone.

  @text_fields ~w(title credits alt caption)

  @doc """
  Casts an override from editor params.

  The editor submits only the texts; an empty text inherits the media's own.
  Each `use_default_*` flag is derived from its text when the params carry the
  text but not the flag, so the flag the renderer reads always agrees with what
  the editor shows. Params that set a flag explicitly keep it.
  """
  def cast_override(override, params) do
    override
    |> changeset(params)
    |> derive_use_default(params)
  end

  defp derive_use_default(changeset, params) when is_map(params) do
    Enum.reduce(@text_fields, changeset, fn field, acc ->
      flag = "use_default_" <> field

      if param?(params, field) and not param?(params, flag) do
        Ecto.Changeset.put_change(acc, String.to_existing_atom(flag), not Brando.Captions.present?(param(params, field)))
      else
        acc
      end
    end)
  end

  defp derive_use_default(changeset, _params), do: changeset

  defp param?(params, key), do: Map.has_key?(params, key) or Map.has_key?(params, String.to_existing_atom(key))
  defp param(params, key), do: Map.get(params, key, Map.get(params, String.to_existing_atom(key)))

  @doc """
  Returns `{object_type, object_id}` for an override given as a struct, a plain
  map (atom or string keys) or a changeset. `object_type` is `nil` when the
  override has none.
  """
  def media_key(%Ecto.Changeset{} = override) do
    media_key(%{
      object_id: Ecto.Changeset.get_field(override, :object_id),
      object_type: Ecto.Changeset.get_field(override, :object_type)
    })
  end

  def media_key(%{object_id: id} = override) when not is_nil(id) and id != "",
    do: {media_type(Map.get(override, :object_type)), to_string(id)}

  def media_key(%{"object_id" => id} = override) when not is_nil(id) and id != "",
    do: {media_type(Map.get(override, "object_type")), to_string(id)}

  def media_key(_), do: nil

  @doc """
  Whether `override` applies to the `type` media (`:image` or `:video`) with `id`.
  """
  def for_media?(override, type, id) do
    case media_key(override) do
      {nil, override_id} -> override_id == to_string(id)
      {override_type, override_id} -> override_type == type && override_id == to_string(id)
      nil -> false
    end
  end

  @doc """
  Indexes overrides by media for `lookup/3`. A later override for the same media
  replaces an earlier one.
  """
  def index(overrides) do
    Enum.reduce(overrides || [], %{}, fn override, acc ->
      case media_key(override) do
        nil -> acc
        key -> Map.put(acc, key, override)
      end
    end)
  end

  @doc """
  Finds the override for the `type` media with `id` in an `index/1` map,
  preferring a typed override over one stored without a type.
  """
  def lookup(index, type, id) do
    id = to_string(id)
    Map.get(index, {type, id}) || Map.get(index, {nil, id})
  end

  defp media_type(type) when type in [:image, :video], do: type
  defp media_type("image"), do: :image
  defp media_type("video"), do: :video
  defp media_type(_), do: nil
end
