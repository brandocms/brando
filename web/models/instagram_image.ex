defmodule Brando.InstagramImage do
  @moduledoc """
  Ecto schema for the InstagramImage model
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Brando.Web, :model
  import Brando.Gettext
  import Ecto.Query, only: [from: 2]
  require Logger
  alias Brando.Instagram
  alias Brando.Exception.UploadError

  @cfg Application.get_env(:brando, Brando.Instagram)

  @required_fields ~w(instagram_id caption link url_original username
                      url_thumbnail created_time type status)
  @optional_fields ~w(image)

  schema "instagramimages" do
    field :instagram_id, :string
    field :type, :string
    field :caption, :string
    field :link, :string
    field :username, :string
    field :url_original, :string
    field :url_thumbnail, :string
    field :image, Brando.Type.Image
    field :created_time, :string
    field :status, Brando.Type.InstagramStatus, default: :rejected
  end

  @doc """
  Casts and validates `params` against `model` to create a valid
  changeset when action is :create.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, atom, Keyword.t | Options.t) :: t
  def changeset(model, :create, params) do
    status =
      case params["image"] do
        nil -> :download_failed
        _   -> @cfg[:auto_approve] && :approved || :rejected
      end

    model
    |> cast(params, @required_fields, @optional_fields)
    |> unique_constraint(:instagram_id)
    |> put_change(:status, status)
  end

  @doc """
  Casts and validates `params` against `model` to create a valid
  changeset when action is :update.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :update, params)

  """
  @spec changeset(t, atom, %{binary => term} | %{atom => term}) :: t
  def changeset(model, :update, params) do
    status =
      if model.status == :download_failed && params["image"] do
        @cfg[:auto_approve] && :approved || :rejected
      else
        model.status
      end

    model
    |> cast(params, [], @required_fields ++ @optional_fields)
    |> put_change(:status, status)
  end

  @doc """
  Create a changeset for the model by passing `params`.
  If not valid, return errors from changeset
  """
  @spec create(%{binary => term} | %{atom => term})
        :: {:ok, t} | {:error, Keyword.t}
  def create(params) do
    if image = Brando.repo.get_by(__MODULE__,
                                  instagram_id: params["instagram_id"]) do
      image
      |> changeset(:update, params)
      |> Brando.repo.update
    else
      %__MODULE__{}
      |> changeset(:create, params)
      |> Brando.repo.insert
    end
  end

  @doc """
  Create an `update` changeset for the model by passing `params`.
  If valid, update model in Brando.repo.
  If not valid, return errors from changeset
  """
  @spec update(t, %{binary => term} | %{atom => term})
        :: {:ok, t} | {:error, Keyword.t}
  def update(model, params) do
    model_changeset = changeset(model, :update, params)
    case model_changeset.valid? do
      true ->  {:ok, Brando.repo.update!(model_changeset)}
      false -> {:error, model_changeset.errors}
    end
  end

  @doc """
  Takes a map provided from the API and transforms it to a map we can
  use to store in the DB.
  """
  def store_image(%{"id" => instagram_id, "caption" => caption, "user" => user,
                    "images" => %{"thumbnail" => %{"url" => thumb},
                    "standard_resolution" => %{"url" => org}}} = image) do
    image
    |> Map.merge(%{"username" => user["username"],
                   "instagram_id" => instagram_id,
                   "caption" => caption && caption["text"] || "",
                   "url_thumbnail" => thumb, "url_original" => org})
    |> Map.drop(["images", "id"])
    |> download_image
    |> create_image_sizes
    |> create
  end

  defp download_image(image) do
    image_field = %Brando.Type.Image{}
    url = Map.get(image, "url_original")

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{body: _, status_code: 404}} ->
        Logger.error("Instagram: Feil fra Instagram API. " <>
                     "Kunne ikke laste ned bilde.\nURL: #{url}")
        image
        |> Map.put("image", nil)
        |> Map.put("status", :download_failed)
      {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
        media_path = Brando.config(:media_path)
        instagram_path = Instagram.config(:upload_path)
        path = Path.join([media_path, instagram_path])
        case File.mkdir_p(path) do
          :ok ->
            file = Path.join([path, Path.basename(url)])
            File.write!(file, body)
            image_field = Map.put(image_field, :path, Path.join([instagram_path,
                                                      Path.basename(url)]))
            Map.put(image, "image", image_field)
          {:error, reason} ->
            raise UploadError,
                  message: "Kunne ikke lage filbane -> #{inspect(reason)}"
        end
      {:error, err} ->
        {:error, err}
    end
  end

  defp create_image_sizes(%{"image" => nil} = image_model) do
    image_model
  end
  defp create_image_sizes(image_model) do
    sizes_cfg = Brando.Instagram.config(:sizes)
    if sizes_cfg != nil do
      image_field = image_model["image"]
      media_path = Brando.config(:media_path)

      full_path = Path.join([media_path, image_field.path])
      {file_path, filename} = Brando.Utils.split_path(full_path)

      sizes = for {size_name, size_cfg} <- sizes_cfg do
        size_dir = Path.join([file_path, to_string(size_name)])
        File.mkdir_p(size_dir)
        sized_image = Path.join([size_dir, filename])
        Brando.Images.Utils.create_image_size(full_path, sized_image, size_cfg)
        sized_path = Path.join([Brando.Instagram.config(:upload_path),
                                to_string(size_name), filename])
        {size_name, sized_path}
      end
      image_field = Map.put(image_field, :sizes, Enum.into(sizes, %{}))
      Map.put(image_model, "image", image_field)
    else
      image_model
    end
  end

  @doc """
  Get timestamp from where we search for new images
  """
  def get_last_created_time do
    q = from m in __MODULE__,
             select: m.created_time,
             order_by: [desc: m.created_time],
             limit: 1
      max = Brando.repo.one(q)

    case max do
      nil -> :blank
      max -> max
             |> String.to_integer
             |> Kernel.+(1)
             |> Integer.to_string
    end
  end

  def get_failed_downloads do
    q = from m in __MODULE__,
             where: m.status == 3
    Brando.repo.all(q)
  end

  @doc """
  Get min_id from where we search for new images
  """
  def get_min_id do
    q = from m in __MODULE__,
             select: m.instagram_id,
             order_by: [desc: m.instagram_id],
             limit: 1
      id = Brando.repo.one(q)

    case id do
      nil -> :blank
      id -> Enum.at(String.split(id, "_"), 0)
    end
  end

  @doc false
  defmacro update_all(queryable, values, opts \\ []) do
    Ecto.Repo.Queryable.update_all(Brando.repo, Ecto.Adapters.Postgres,
                                   queryable, values, opts)
  end

  def change_status_for(ids, status) when is_list(ids)
                                     and status in ["0", "1", "2"] do
    ids = Enum.map(ids, fn(id) -> String.to_integer(id) end)
    q = from m in __MODULE__,
             where: m.id in ^ids

    Brando.repo.update_all(q, set: [status: status])
  end

  @doc """
  Delete `record` from database

  Also deletes all dependent image sizes.
  """
  def delete(ids) when is_list(ids) do
    for id <- ids, do:
      delete(id)
  end

  def delete(record) when is_map(record) do
    Brando.repo.delete!(record)
  end

  def delete(id) do
    record = Brando.repo.get_by!(__MODULE__, id: id)
    delete(record)
  end

  #
  # Meta

  use Brando.Meta.Model, [
    singular: gettext("instagram image"),
    plural: gettext("instagram images"),
    repr: &("#{&1.id} | #{&1.caption}"),
    fields: [
      id: gettext("ID"),
      instagram_id: gettext("Instagram ID"),
      type: gettext("Type"),
      caption: gettext("Caption"),
      link: gettext("Link"),
      url_original: gettext("Image URL"),
      url_thumbnail: gettext("Thumbnail URL"),
      created_time: gettext("Created"),
      status: gettext("Status"),
    ]
  ]

end
