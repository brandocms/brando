defmodule Brando.Images do
  @moduledoc """
  Context for Images.
  Handles uploads too.
  Interfaces with database

  ## Image config

  You can configure a picture block ref by setting the `config_target` field to a string like this:

      image:Elixir.MyApp.Pages.Page:function:sidebar_image_config

  then in the module `MyApp.Pages.Page` you can define a function like this:

      def sidebar_image_config do
        %Brando.Type.ImageConfig{
          upload_path: Path.join(["images", "CUSTOM", "SIDEBAR"]),
          # ...
        }
      end
  """
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.Images
  alias Brando.Images.Image
  alias Brando.Users.User

  @type id :: binary | integer
  @type changeset :: changeset
  @type params :: map
  @type user :: User.t()

  query :single, Image, do: fn query -> from(t in query) end

  matches Image do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id
    end
  end

  query :list, Image, do: fn query -> from(t in query) end

  filters Image do
    fn
      {:ids, ids}, query ->
        from t in query, where: t.id in ^ids

      {:config_target, nil}, query ->
        from(t in query)

      {:config_target, "default"}, query ->
        target_string = "default"
        from t in query, where: t.config_target == ^target_string

      {:config_target, target_string}, query when is_binary(target_string) ->
        from t in query, where: t.config_target == ^target_string

      {:config_target, {type, schema, field}}, query ->
        target_string = "#{type}:#{inspect(schema)}:#{field}"
        from t in query, where: t.config_target == ^target_string

      {:config_target_search, target_string}, query when is_binary(target_string) ->
        from t in query, where: ilike(t.config_target, ^"%#{target_string}%")

      {:path, path}, query ->
        from q in query, where: ilike(q.path, ^"%#{path}%")

      {:unused, value}, query when value in [true, "true"] ->
        from(t in query, where: t.id not in ^Brando.Content.Usage.used_ids(:image))

      {:unused, _}, query ->
        query

      # The root: entries without a folder, and those in a folder that is the root itself.
      {:folder_id, {:root, root_folder_ids}}, query ->
        from(t in query, where: is_nil(t.folder_id) or t.folder_id in ^root_folder_ids)

      # Every library folder and the root: all but the hidden folders.
      {:folder_id, {:library, hidden_folder_ids}}, query ->
        from(t in query, where: is_nil(t.folder_id) or t.folder_id not in ^hidden_folder_ids)

      {:folder_id, folder_id}, query ->
        case normalize_folder_id(folder_id) do
          nil -> from(t in query, where: is_nil(t.folder_id))
          id -> from(t in query, where: t.folder_id == ^id)
        end

      {:status, status}, query ->
        from t in query, where: t.status == ^status

      # Leave out images in hidden folders (`hidden_folder` configs)
      {:library, true}, query ->
        from t in query,
          left_join: f in Brando.Media.Folder,
          on: f.id == t.folder_id,
          where: is_nil(f.id) or f.library

      {:library, _}, query ->
        query
    end
  end

  mutation :update, Image
  mutation :delete, Image

  @doc """
  Create new image
  """
  @spec create_image(params, user) :: {:ok, Image.t()} | {:error, changeset}
  def create_image(params, user) do
    %Image{}
    |> Image.changeset(params, user)
    |> Brando.Repo.insert()
  end

  @doc """
  Get image.
  Raises on failure
  """
  def get_image!(id) do
    query =
      from t in Image,
        where: t.id == ^id and is_nil(t.deleted_at)

    Brando.Repo.one!(query)
  end

  @doc """
  An earlier image of the same file as `image` (the same `content_hash`) made
  for the same image config, not deleted, or nil. Only uploads have a hash, so
  copies made with "Duplicate" are never offered in place of an upload. One
  made for another config has that config's sizes, not the ones the upload's
  field renders.
  """
  def find_duplicate(%Image{content_hash: hash, id: id, config_target: config_target}) when is_binary(hash) do
    hash
    |> same_file_query(config_target)
    |> where([i], i.id != ^id)
    |> Brando.Repo.one()
  end

  def find_duplicate(_image), do: nil

  defp same_file_query(hash, config_target) do
    query =
      from(i in Image,
        where: i.content_hash == ^hash and is_nil(i.deleted_at),
        order_by: [asc: i.id],
        limit: 1
      )

    if config_target,
      do: where(query, [i], i.config_target == ^config_target),
      else: where(query, [i], is_nil(i.config_target))
  end

  @doc """
  `image` made for `config_target`, the image config of the field, ref or var
  it is picked for.

  An image is processed into its own config's sizes and formats, and renders
  by their names, so an image made for another config is not used as it is:
  this returns an earlier copy of the same file made for `config_target` (the
  same `content_hash`), or makes one. A new copy is the original file copied
  into the config's upload path, as an upload to the field would put it, and
  queued for processing; it keeps the image's texts and focal point. `image`
  itself is never changed, so what shows it keeps its sizes.
  """
  @spec for_config_target(Image.t(), String.t(), user) :: {:ok, Image.t()} | {:error, term()}
  def for_config_target(%Image{config_target: config_target} = image, config_target, _user), do: {:ok, image}

  def for_config_target(%Image{} = image, config_target, user) when is_binary(config_target) do
    existing = if is_binary(image.content_hash), do: Brando.Repo.one(same_file_query(image.content_hash, config_target))

    case existing do
      %Image{} = copy -> {:ok, copy}
      nil -> copy_for_config_target(image, config_target, user)
    end
  end

  defp copy_for_config_target(image, config_target, user) do
    {:ok, cfg} = get_config_for(config_target)
    path = Path.join(cfg.upload_path, Brando.Utils.unique_filename(Path.basename(image.path)))
    dest = Images.Utils.media_path(path)

    with :ok <- File.mkdir_p(Path.dirname(dest)),
         :ok <- File.cp(Images.Utils.media_path(image.path), dest),
         {:ok, copy} <-
           create_image(
             %{
               path: path,
               config_target: config_target,
               content_hash: image.content_hash,
               width: image.width,
               height: image.height,
               dominant_color: image.dominant_color,
               title: image.title,
               credits: image.credits,
               alt: image.alt,
               focal: if(image.focal, do: Map.take(image.focal, [:x, :y]), else: %{x: 50, y: 50}),
               sizes: %{},
               status: :unprocessed,
               folder_id: Brando.Media.Folders.upload_folder_id(nil, cfg)
             },
             user
           ),
         {:ok, _job} <- Images.Processing.queue_processing(copy, user) do
      {:ok, copy}
    end
  end

  @doc """
  Delete `ids` from database
  Also deletes all dependent image sizes.
  """
  def delete_images(ids) when is_list(ids) do
    q = from m in Image, where: m.id in ^ids
    Brando.Repo.soft_delete_all(q)
  end

  @doc "Returns the image orientation for dimensions or an image-like map."
  defdelegate get_image_orientation(width, height), to: Brando.Images.Metadata, as: :orientation

  @doc "Returns the image orientation for an image-like map."
  defdelegate get_image_orientation(image), to: Brando.Images.Metadata, as: :orientation

  @doc "Resolves the image configuration for an image or stored config target."
  defdelegate get_config_for(image_or_target), to: Brando.Images.ConfigResolver, as: :get

  def get_processed_formats(path, nil) do
    original_type = Images.Utils.image_type(path)
    List.wrap(remap_format(original_type))
  end

  def get_processed_formats(path, formats) do
    original_type = Images.Utils.image_type(path)

    Enum.map(formats, fn
      :original -> remap_format(original_type)
      format -> remap_format(format)
    end)
  end

  defp remap_format(:gif), do: :webp
  defp remap_format(format), do: format

  @doc """
  An image's `:alt`, `:title` or `:credits` in `language`: that language's
  text, else the default content language's, else `nil`.

  These fields are maps of language → text. Pass the language explicitly —
  the entry's when rendering its blocks, the request's in a template — rather
  than relying on the current locale: blocks are rendered in the admin, under
  the editor's locale.

  Plain strings (block data saved before the fields were translated, or a
  map already resolved) are returned as they are.

      Brando.Images.text(image, :alt, "no")
  """
  @spec text(map() | nil, :alt | :title | :credits, String.t() | atom() | nil) :: String.t() | nil
  def text(nil, _field, _language), do: nil

  def text(image, field, language) when field in [:alt, :title, :credits] do
    image |> Map.get(field) |> Brando.Type.I18nString.get(language)
  end

  @doc """
  `image` — or picture data merged from one — with `:title`, `:credits` and
  `:alt` as text in `language`: the image's language maps resolved, a
  placement's override strings left as they are. Renderers call this once,
  where the language is known, so nothing downstream sees a map.
  """
  @spec resolve_texts(map(), String.t() | atom() | nil) :: map()
  def resolve_texts(image, language) when is_map(image) do
    Enum.reduce([:title, :credits, :alt], image, fn field, acc ->
      case Map.fetch(acc, field) do
        {:ok, value} when is_map(value) -> Map.put(acc, field, Brando.Type.I18nString.get(value, language))
        _ -> acc
      end
    end)
  end

  def resolve_texts(image, _language), do: image

  def list_generated_sizes(image) do
    {:ok, %{formats: _formats, sizes: _sizes}} = get_config_for(image)
  end

  def duplicate_image(image_id, user) do
    original_image = get_image!(image_id)

    src_file =
      :media_path
      |> Brando.config()
      |> Path.join(original_image.path)

    new_file = Brando.Utils.unique_filename(original_image.path)

    dest_file =
      :media_path
      |> Brando.config()
      |> Path.join(new_file)

    with :ok <- File.cp(src_file, dest_file) do
      new_image_params =
        original_image
        |> Brando.Utils.map_from_struct()
        |> Map.drop([:id, :inserted_at, :updated_at])
        |> Map.put(:path, new_file)
        |> Map.put(:sizes, %{})
        |> Map.put(:status, :unprocessed)
        # A deliberate copy (another crop, say) is never offered in place of
        # an upload of the same file
        |> Map.put(:content_hash, nil)
        |> Map.put(:config_fingerprint, nil)

      create_image(new_image_params, user)
    end
  end

  defp normalize_folder_id(nil), do: nil
  defp normalize_folder_id(""), do: nil
  defp normalize_folder_id(folder_id) when is_integer(folder_id), do: folder_id

  defp normalize_folder_id(folder_id) when is_binary(folder_id) do
    case Integer.parse(folder_id) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp normalize_folder_id(_), do: nil
end
