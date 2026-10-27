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

  alias Brando.Authorization.Boundary
  alias Brando.Images
  alias Brando.Images.Image
  alias Brando.Repo
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
    |> Repo.insert()
  end

  @doc """
  Get image.
  Raises on failure
  """
  def get_image!(id) do
    query =
      from t in Image,
        where: t.id == ^id and is_nil(t.deleted_at)

    Repo.one!(query)
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
    |> Repo.one()
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
  this returns the copy of the same file made for `config_target`, or makes
  one. A copy is the original file in the config's upload path, as an upload
  to the field would put it, queued for processing; it keeps the image's
  texts and focal point. `image` itself is never changed, so what shows it
  keeps its sizes.

  The file is what identifies a copy: its `content_hash`, the SHA-256 of the
  original. An image uploaded before Brando stored hashes gets its hash
  recorded on the first pick, so later picks find the copy. The original is
  read from the media folder, or from the CDN when only the CDN has it
  (`keep_local_copy: false`). Picks of one file for one config are taken one
  at a time (a transaction-scoped advisory lock), so two editors picking it
  at once get the same copy. A copy whose processing never got queued is
  queued again.
  """
  @spec for_config_target(Image.t(), String.t(), user) :: {:ok, Image.t()} | {:error, term()}
  def for_config_target(%Image{config_target: config_target} = image, config_target, _user), do: {:ok, image}

  def for_config_target(%Image{} = image, config_target, user) when is_binary(config_target) do
    with {:ok, hash, original} <- source_hash(image) do
      Repo.transaction(fn -> copy_once(image, hash, original, config_target, user) end)
    end
  end

  # In the transaction: one pick of the file for the config at a time
  defp copy_once(image, hash, original, config_target, user) do
    lock_copy(hash, config_target)
    if is_nil(image.content_hash), do: record_hash(image, hash)

    result =
      case Repo.one(same_file_query(hash, config_target)) do
        %Image{} = copy -> requeue_unqueued(copy, user)
        nil -> copy_for_config_target(%{image | content_hash: hash}, original, config_target, user)
      end

    case result do
      {:ok, copy} -> copy
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # The hash identifies the copies; the original is read only when it is not
  # stored, or when a copy has to be made (`original` is then a function).
  defp source_hash(%Image{content_hash: hash} = image) when is_binary(hash),
    do: {:ok, hash, fn -> read_original(image) end}

  defp source_hash(image) do
    with {:ok, bytes} <- read_original(image) do
      {:ok, :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower), fn -> {:ok, bytes} end}
    end
  end

  @doc """
  Puts `image`'s original back in the media folder from the CDN it was
  uploaded to, when the folder doesn't have it and the CDN keeps no local
  copy (`keep_local_copy: false`): the original was removed once uploaded,
  and processing reads it from the folder, so recreating the image's sizes
  needs it there. Delivering the sizes to the CDN removes it again; a run
  that doesn't get that far removes it with `discard_restored_original/2`.

  `{:ok, :restored}` when it was fetched, `{:ok, :unchanged}` otherwise. An
  original missing where local copies are kept is not fetched: the folder
  is more likely empty or not mounted (a copy of production's config on
  another machine), and processing fails on the missing file, as before.
  """
  @spec restore_original(Image.t()) :: {:ok, :restored | :unchanged} | {:error, term}
  def restore_original(%Image{path: path} = image) when is_binary(path) do
    with {:ok, file} <- media_file(path) do
      case not File.exists?(file) && delivery_cdn(image) do
        {cfg, cdn} -> download_original(image, file, Map.put(cfg, :cdn, cdn))
        _ -> {:ok, :unchanged}
      end
    end
  end

  def restore_original(_image), do: {:ok, :unchanged}

  @doc "Removes the original `restore_original/1` fetched, when it did (`:restored`)."
  @spec discard_restored_original(Image.t(), :restored | :unchanged) :: :ok
  def discard_restored_original(%Image{path: path}, :restored) do
    with {:ok, file} <- media_file(path), do: File.rm(file)
    :ok
  end

  def discard_restored_original(_image, _restored), do: :ok

  # The CDN the original was delivered to, when it keeps no local copy
  defp delivery_cdn(image) do
    {:ok, cfg} = get_config_for(image)

    case effective_cdn(cfg) do
      %{enabled: true, keep_local_copy: false} = cdn -> {cfg, cdn}
      _ -> nil
    end
  end

  # Written beside it, under a name of its own (two recreations of the image
  # may run at once), and moved into place, so processing never reads a
  # partly written original
  defp download_original(image, file, field_cfg) do
    partial = "#{file}.download-#{Base.url_encode64(:crypto.strong_rand_bytes(9))}"

    with {:cdn, {:ok, bytes}} <- {:cdn, Brando.CDN.get_object(Path.join("media", image.path), field_cfg)},
         :ok <- File.mkdir_p(Path.dirname(file)),
         :ok <- File.write(partial, bytes),
         :ok <- File.rename(partial, file) do
      {:ok, :restored}
    else
      {:cdn, error} ->
        error

      error ->
        File.rm(partial)
        error
    end
  end

  defp read_original(image) do
    with {:ok, path} <- media_file(image.path),
         {:error, :enoent} <- File.read(path) do
      read_original_from_cdn(image)
    end
  end

  # The CDN the original was uploaded to: its config's own, or, as the
  # uploader falls back to it, the one configured for `Brando.Images`
  defp read_original_from_cdn(image) do
    {:ok, cfg} = get_config_for(image)

    case effective_cdn(cfg) do
      %{enabled: true} = cdn -> Brando.CDN.get_object(Path.join("media", image.path), Map.put(cfg, :cdn, cdn))
      _ -> {:error, :enoent}
    end
  end

  defp effective_cdn(%{cdn: %{enabled: true} = cdn}), do: cdn
  defp effective_cdn(_cfg), do: Brando.CDN.config(Brando.Images)

  defp lock_copy(hash, config_target) do
    key = :erlang.phash2({Brando.Tenant.current_prefix(), hash, config_target}, 4_294_967_296)
    Repo.repo().query!("SELECT pg_advisory_xact_lock($1)", [key])
  end

  defp record_hash(image, hash) do
    Repo.update_all(from(i in Image, where: i.id == ^image.id and is_nil(i.content_hash)),
      set: [content_hash: hash]
    )
  end

  defp requeue_unqueued(%Image{status: :unprocessed} = copy, user) do
    if Images.Processing.processing_queued?(copy) do
      {:ok, copy}
    else
      with {:ok, _job} <- Images.Processing.queue_processing(copy, user), do: {:ok, copy}
    end
  end

  defp requeue_unqueued(copy, _user), do: {:ok, copy}

  defp copy_for_config_target(image, original, config_target, user) do
    {:ok, cfg} = get_config_for(config_target)
    path = Path.join(cfg.upload_path, Brando.Utils.unique_filename(Path.basename(image.path)))
    dest = Images.Utils.media_path(path)

    with {:ok, bytes} <- original.(),
         :ok <- File.mkdir_p(Path.dirname(dest)),
         :ok <- File.write(dest, bytes),
         {:ok, copy} <- create_copy(image, path, config_target, cfg, user, dest),
         {:ok, _job} <- Images.Processing.queue_processing(copy, user) do
      {:ok, copy}
    end
  end

  defp create_copy(image, path, config_target, cfg, user, dest) do
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
    }
    |> create_image(user)
    |> case do
      {:ok, copy} ->
        {:ok, copy}

      error ->
        File.rm(dest)
        error
    end
  end

  @doc """
  Soft-deletes the images `ids` on behalf of `actor`, who needs `:delete` on
  images. With groups authorization only the images the actor may delete go;
  `{:error, :forbidden}` without the grant.
  """
  def delete_images(ids, actor \\ :system) when is_list(ids) do
    Boundary.run(actor, :delete, Image, fn _user ->
      allowed =
        Boundary.with_query_action(:delete, Image, fn ->
          from(m in Image, where: m.id in ^ids, select: m.id) |> Boundary.query(Image) |> Repo.all()
        end)

      Repo.soft_delete_all(from(m in Image, where: m.id in ^allowed))
    end)
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

  @doc """
  Copies the image `image_id`, file and all, on behalf of `user`, who needs
  to read it and `:create` images.
  """
  def duplicate_image(image_id, user) do
    with :ok <- Boundary.authorize(user, :create, Image),
         :ok <- Boundary.authorize_record(user, :read, Image, image_id),
         do: do_duplicate_image(image_id, user)
  end

  defp do_duplicate_image(image_id, user) do
    original_image = get_image!(image_id)
    new_file = Brando.Utils.unique_filename(original_image.path)

    with {:ok, src_file} <- media_file(original_image.path),
         {:ok, dest_file} <- media_file(new_file),
         :ok <- File.cp(src_file, dest_file) do
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

  # A stored path, joined with the current media root unless it would leave it
  defp media_file(path) do
    case Brando.Tenant.Storage.media_file(path) do
      {:ok, file} -> {:ok, file}
      :error -> {:error, :unsafe_media_path}
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
