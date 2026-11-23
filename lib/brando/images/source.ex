defmodule Brando.Images.Source do
  @moduledoc """
  Where an image's file came from: a picture of another service (`source`,
  `"figma"` today), by that service's reference to it (`ref`, Figma's
  `imageRef`), with what else made the stored file differ from the picture
  (`variant`: for Figma, the quarter turn the layers showing it have, `"90"`,
  `"180"` or `"270"`) and the image config it was stored for.

  `Brando.Figma.Import` records it for every image it stores or reuses, and
  `brando_figma_read_frame` names, for each layer, the library image the
  last imports gave its picture (`Brando.Figma.Import.put_assets/2`).

  One picture can have several images: turned for one layer and not for
  another, stored by two people who may not read each other's images,
  imported again after the first went to the trash, or scaled down to fit
  the site's upload limit. A row goes with its image, and moves to the image
  that takes its file (`Brando.Content.Proposals.ImageReplacement`).
  """
  use Ecto.Schema

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Transfer.Catalog
  alias Brando.Images.Image
  alias Brando.Repo

  require Logger

  @type t :: %__MODULE__{}

  schema "images_sources" do
    belongs_to :image, Image
    field :source, :string
    field :ref, :string
    field :variant, :string
    field :config_target, :string

    timestamps(updated_at: false)
  end

  @doc """
  Records that `image` holds `ref`'s picture from `source`, as `variant`,
  stored for `config_target`. Once per image, source, ref and variant. A
  row that cannot be written is logged and left out: it never fails what
  stored the image.
  """
  @spec record(Image.t(), String.t(), String.t(), String.t() | nil, String.t()) :: :ok | :error
  def record(%Image{id: image_id}, source, ref, variant, config_target) do
    row = %{
      image_id: image_id,
      source: source,
      ref: ref,
      variant: variant,
      config_target: config_target,
      inserted_at: NaiveDateTime.utc_now(:second)
    }

    # Inside a caller's transaction, a failure would otherwise abort it
    savepoint = if Repo.repo().in_transaction?(), do: [mode: :savepoint], else: []
    Repo.insert_all(__MODULE__, [row], [on_conflict: :nothing] ++ savepoint)
    :ok
  rescue
    error ->
      Logger.warning(
        "[Brando.Images.Source] Could not record #{source} #{ref} for image #{image_id}: " <> Exception.message(error)
      )

      :error
  end

  @doc """
  For each `{ref, variant}` of `source` among `keys`, the image `actor` may
  read, out of the trash, recorded for `config_target`: the lowest id when
  several are, as `Brando.Images.Intake` reuses the oldest. A key without one
  is left out.
  """
  @spec images(String.t(), [{String.t(), String.t() | nil}], String.t(), term()) :: %{
          {String.t(), String.t() | nil} => pos_integer()
        }
  def images(_source, [], _config_target, _actor), do: %{}

  def images(source, keys, config_target, actor) do
    wanted = MapSet.new(keys)
    refs = keys |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    readable =
      from(i in Image, where: is_nil(i.deleted_at), select: i.id)
      |> Catalog.scoped_query(Image, actor, :read)

    from(s in __MODULE__,
      where:
        s.source == ^source and s.ref in ^refs and s.config_target == ^config_target and
          s.image_id in subquery(readable),
      group_by: [s.ref, s.variant],
      select: {{s.ref, s.variant}, min(s.image_id)}
    )
    |> Repo.all()
    |> Map.new()
    |> Map.filter(fn {key, _id} -> MapSet.member?(wanted, key) end)
  end

  @doc """
  `to` took the file of `from`, whose record goes: `to`'s sources are no
  longer its file's, and `from`'s are, for `to`'s config (none matches an
  image without one, as `Brando.Images.Intake` reuses none).
  """
  @spec hand_over(Image.t(), Image.t()) :: :ok
  def hand_over(%Image{id: from_id}, %Image{id: to_id, config_target: config_target}) do
    Repo.delete_all(from(s in __MODULE__, where: s.image_id == ^to_id))

    Repo.update_all(from(s in __MODULE__, where: s.image_id == ^from_id),
      set: [image_id: to_id, config_target: config_target]
    )

    :ok
  end
end
