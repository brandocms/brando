defmodule Brando.Images.Intake do
  @moduledoc """
  Puts a file a connected tool brought into the media library, as an
  editor's upload there would be: the Figma import (`Brando.Figma.Import`)
  and the media tools of the MCP endpoint (`Brando.MCP.Media`).

  The file is stored with `Brando.Uploads.store_upload/4` under the default
  image config, in a folder below its upload path, never over a file already
  stored. An image the library already has (the same file, by content hash,
  for the same config, that the person may read) is reused rather than
  stored again. One store of a file for the config runs at a time
  (`Brando.Images.with_file_lock/3`), so two imports of the same picture at
  once find each other's image; the folder is made before that lock's
  transaction, so two stores into a new folder at once both use it. Sizes
  are made in the background.

  A download from a URL goes through `Brando.Webhooks.URLGuard`: public
  `https` addresses only, no redirects, at most the config's size limit.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Transfer.Catalog
  alias Brando.Images
  alias Brando.Images.Image
  alias Brando.Uploads
  alias Brando.Uploads.ContentType
  alias Brando.Webhooks.Client
  alias Brando.Webhooks.URLGuard
  alias BrandoAdmin.Images.FolderBrowser

  require Logger

  @type context :: %{
          cfg: struct(),
          config_target: String.t(),
          upload_root: String.t() | nil,
          absolute_folder: String.t() | nil,
          folder: String.t() | nil,
          actor: term()
        }

  @exts %{
    "image/jpeg" => "jpg",
    "image/png" => "png",
    "image/gif" => "gif",
    "image/webp" => "webp",
    "image/avif" => "avif",
    "image/svg+xml" => "svg"
  }

  @doc """
  Where `actor`'s files go: the default image config, with `folder` (a path
  below its upload path, or one that starts with it) as the upload path and
  overwriting off. The library folder is created, if `actor` may add one,
  when `store/6` is about to store a new image in it: not for a file the
  library already has. A file the store then refuses (over the pixel limit,
  an SVG it does not take) leaves the folder.
  """
  @spec context(term(), String.t() | nil) :: context()
  def context(actor, folder) do
    {cfg, config_target} = Uploads.resolve_image_config(nil)
    root = FolderBrowser.upload_root(config_target)
    absolute = FolderBrowser.absolute_folder(folder, root)
    cfg = cfg |> Map.put(:upload_path, absolute) |> Map.put(:overwrite, false)

    %{
      cfg: cfg,
      config_target: config_target,
      upload_root: root,
      absolute_folder: absolute,
      folder: FolderBrowser.relative_folder(absolute, root),
      actor: actor
    }
  end

  @doc "The library folder `image` is in, below its config's upload path, or nil."
  @spec folder(Image.t()) :: String.t() | nil
  def folder(%Image{} = image) do
    case FolderBrowser.folder_path_for_id(image.folder_id, FolderBrowser.upload_root(image.config_target)) do
      "" -> nil
      folder -> folder
    end
  end

  @doc "The most bytes a file for `cfg` may have."
  @spec size_limit(map()) :: pos_integer()
  def size_limit(cfg) do
    case Map.get(cfg, :size_limit) do
      limit when is_integer(limit) and limit > 0 -> limit
      _ -> Uploads.max_file_size()
    end
  end

  @doc "The image types the default image config takes, of those a tool can bring."
  @spec allowed_types() :: [String.t()]
  def allowed_types do
    {cfg, _target} = Uploads.resolve_image_config(nil)
    allowed_types(cfg)
  end

  @doc "The image types `cfg` takes, of those a tool can bring."
  @spec allowed_types(map()) :: [String.t()]
  def allowed_types(cfg) do
    allowed = Map.get(cfg, :allowed_mimetypes) || []
    for type <- Map.keys(@exts), allowed == ["*"] or type in allowed, do: type
  end

  @doc """
  The image type `head`, the first bytes of a file, holds, and its
  extension, when `cfg` takes it: `{:ok, type, ext}`, or `{:error, message}`.
  """
  @spec image_type(binary(), map()) :: {:ok, String.t(), String.t()} | {:error, String.t()}
  def image_type(head, cfg) do
    type = ContentType.image(head)
    allowed = allowed_types(cfg)

    cond do
      type in allowed -> {:ok, type, Map.fetch!(@exts, type)}
      allowed == [] -> {:error, "The site takes no images."}
      true -> {:error, "Not an image the site takes. It takes #{describe_types(allowed)}."}
    end
  end

  @doc "Image types as a person reads them: JPEG, PNG and WebP."
  @spec describe_types([String.t()]) :: String.t()
  def describe_types(types) do
    names =
      types
      |> Enum.sort()
      |> Enum.map(fn
        "image/svg+xml" -> "SVG"
        "image/webp" -> "WebP"
        "image/" <> name -> String.upcase(name)
      end)

    case Enum.split(names, -1) do
      {[], [one]} -> one
      {names, [last]} -> Enum.join(names, ", ") <> " and " <> last
      {[], []} -> ""
    end
  end

  @doc "The SHA-256 of the file at `path`, as `Image.content_hash` holds it."
  @spec hash(Path.t()) :: String.t()
  def hash(path) do
    path
    |> File.stream!(1_048_576)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  @doc """
  Stores the file at `path` as `filename` of `type`, or reuses the image the
  library has of the same bytes. A new image is created with `attrs` (its
  `focal`, `title` and `alt`), under the permission to create it; a reused
  one keeps its own. `on_new` is called with a new image inside the file
  lock, and returns what to report for it (`{:stored, image}` or
  `{:stored, image, tag}`). Sizes are queued once the row is committed.

  Returns `{:stored, image}`, `{:stored, image, tag}`, `{:reused, image}` or
  `{:error, message}`.
  """
  @spec store(Path.t(), String.t(), String.t(), context(), (Image.t() -> term()), map()) :: term()
  def store(path, filename, type, ctx, on_new \\ &{:stored, &1}, attrs \\ %{}) do
    hash = hash(path)

    case existing(hash, ctx) do
      %Image{} = image ->
        queue_sizes({:reused, image}, ctx.actor)

      nil ->
        # The folder is made before the store's transaction, and committed:
        # two stores into a new folder at once both insert it, and the one
        # that loses, inside a transaction, could no longer read the other's
        folder_id = FolderBrowser.folder_id_for(ctx.absolute_folder, ctx.upload_root, ctx.actor, Image)

        hash
        |> Images.with_file_lock(ctx.config_target, fn ->
          reuse_or_store(hash, path, filename, type, ctx, folder_id, on_new, attrs)
        end)
        |> queue_sizes(ctx.actor)
    end
  end

  # Looked for again under the lock: the same file stored meanwhile is reused
  defp reuse_or_store(hash, path, filename, type, ctx, folder_id, on_new, attrs) do
    with nil <- existing(hash, ctx),
         {:stored, image} <- store_new(path, filename, type, ctx, folder_id, attrs) do
      on_new.(image)
    else
      %Image{} = image -> {:reused, image}
      error -> error
    end
  end

  defp store_new(path, filename, type, ctx, folder_id, attrs) do
    meta = %{path: path, config_target: ctx.config_target, folder_id: folder_id, image_attrs: attrs}
    entry = %{client_name: filename, client_type: type, client_size: File.stat!(path).size}

    case Uploads.store_upload(meta, entry, ctx.cfg, ctx.actor) do
      {:ok, %Image{} = image} -> {:stored, image}
      {:error, message} -> {:error, message}
    end
  end

  @doc "The image the library has of the file with `hash`, for the context's config, that its actor may read."
  @spec existing(String.t(), context()) :: Image.t() | nil
  def existing(hash, ctx) do
    query =
      from(i in Image,
        where: i.content_hash == ^hash and i.config_target == ^ctx.config_target and is_nil(i.deleted_at),
        order_by: [asc: i.id],
        limit: 1
      )

    query |> Catalog.scoped_query(Image, ctx.actor, :read) |> Brando.Repo.one()
  end

  # A queueing that fails leaves the image unprocessed; importing it again
  # finds it and queues it then
  defp queue_sizes({:stored, image, _tag} = result, actor) do
    queue_sizes({:stored, image}, actor)
    result
  end

  defp queue_sizes({:stored, image} = result, actor) do
    case Images.Processing.queue_processing(image, actor, [], silent: true) do
      {:ok, _job} -> :ok
      error -> Logger.warning("[Brando.Images.Intake] Could not queue image #{image.id}: #{inspect(error)}")
    end

    result
  end

  defp queue_sizes({:reused, image} = result, actor) do
    Images.ensure_processing_queued(image, actor)
    result
  end

  defp queue_sizes(result, _actor), do: result

  @doc """
  A file name for an image named `name` (a layer or file name; its own
  extension is dropped) of extension `ext`, as a slug, or `fallback` when
  nothing of the name is left. The store makes it unique.
  """
  @spec filename(String.t() | nil, String.t(), String.t()) :: String.t()
  def filename(name, ext, fallback) do
    base =
      (name || "")
      |> Brando.Utils.slugify()
      |> Kernel.||("")
      |> String.slice(0, 80)
      |> String.trim("-")

    if(base == "", do: fallback, else: base) <> "." <> ext
  end

  @doc """
  Downloads `url` to `path` through `Brando.Webhooks.URLGuard`, at most
  `limit` bytes, within `timeout` ms. `{:ok, path}` or `{:error, message}`,
  safe to show; `who` names the server in a message about its answer. With
  `too_large: :size`, a body over `limit` is `{:error, {:too_large, size}}`
  instead, `size` being the bytes the response's `Content-Length` declares,
  or nil.
  """
  @spec download(String.t(), Path.t(), pos_integer(), keyword()) ::
          {:ok, Path.t()} | {:error, String.t() | {:too_large, non_neg_integer() | nil}}
  def download(url, path, limit, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)
    who = Keyword.get(opts, :who, "The server")

    with {:ok, target} <- resolve(url),
         %{status: 200, error: nil} <-
           Client.request(target, "GET", [{"user-agent", "Brando"}], "",
             into: path,
             body_limit: limit,
             timeout: timeout
           ) do
      {:ok, path}
    else
      {:error, message} when is_binary(message) -> {:error, message}
      %{error: :body_too_large} = response -> too_large(response, limit, opts[:too_large])
      %{error: :timeout} -> {:error, "The download took too long."}
      %{error: :unwritable} -> {:error, "The download could not be written to a temporary file."}
      %{status: 200} -> {:error, "The download was cut off. Try again."}
      %{status: status} when status in 300..399 -> {:error, "#{who} answered with a redirect, which is not followed."}
      %{status: status} when is_integer(status) -> {:error, "#{who} answered #{status}."}
      _ -> {:error, "The image could not be downloaded."}
    end
  end

  defp too_large(response, _limit, :size), do: {:error, {:too_large, declared_size(response.headers)}}
  defp too_large(_response, limit, _tag), do: {:error, "The image is larger than #{Brando.Utils.human_size(limit)}."}

  defp declared_size(headers) do
    with {_name, value} <- List.keyfind(headers, "content-length", 0),
         {size, ""} <- Integer.parse(String.trim(value)) do
      size
    else
      _ -> nil
    end
  end

  defp resolve(url) do
    case URLGuard.resolve(url) do
      {:ok, target} -> {:ok, target}
      {:error, reason} -> {:error, guard_message(reason)}
    end
  end

  defp guard_message(reason) when reason in [:https_required, :scheme_not_allowed],
    do: "Only https addresses can be imported."

  defp guard_message(:private_address), do: "The address is not public: it points into a private network."
  defp guard_message(:credentials_in_url), do: "The address may not carry a user name or password."
  defp guard_message(:unresolvable), do: "The address's host could not be found."
  defp guard_message(_reason), do: "That is not an address that can be imported."
end
