defmodule Brando.Content.Transfer.Media do
  @moduledoc "Media staging for archive imports. Only verified originals reach destination-owned paths."
  alias Brando.Content.Transfer.{Archive, Catalog, Dependencies, Error}
  alias Brando.Repo

  def read_original!(kind, record) do
    relative =
      case kind do
        "image" ->
          record.path

        "file" ->
          {:ok, cfg} = Brando.Files.get_config_for(record)
          Path.join(cfg.upload_path, record.filename)
      end

    path = safe_path!(Brando.Tenant.Storage.current_media_root(), relative)

    case File.stat(path) do
      {:ok, %{size: size}} when size > 256_000_000 ->
        Error.fail!(
          "This original exceeds the 256 MB content bundle limit. Export without originals and map a destination asset."
        )

      _ ->
        :ok
    end

    case File.read(path) do
      {:ok, body} ->
        body

      _ ->
        Error.fail!(
          "Original “#{Path.basename(relative)}” is unavailable locally. Restore it from storage, or export without originals and map an existing destination asset."
        )
    end
  end

  def config!(kind, data, actor) do
    target = data["config_target"] || "default"
    {:ok, cfg} = if kind == "image", do: Brando.Images.get_config_for(target), else: Brando.Files.get_config_for(target)

    unless Brando.Authorization.Media.authorize_config(actor, cfg) == :ok,
      do: Error.fail!("You cannot import media into this destination configuration.")

    cfg
  rescue
    _ in [ArgumentError, CaseClauseError, FunctionClauseError, MatchError, UndefinedFunctionError] ->
      Error.fail!(
        "Media configuration “#{data["config_target"]}” is not available on the destination. Map an existing asset or deploy its Blueprint configuration first."
      )
  end

  def validate!(dependency, files, actor) do
    kind = dependency["kind"]
    data = dependency["data"]
    original = dependency["original"] || Error.fail!("Map an existing destination asset; its original is not included.")
    body = files[original["path"]] || Error.fail!("The media original is missing from the archive.")

    unless Archive.checksum(body) == original["sha256"] && byte_size(body) == original["bytes"],
      do: Error.fail!("Media integrity check failed.")

    cfg = config!(kind, data, actor)
    name = Path.basename(data["path"] || data["filename"] || "")
    type = if kind == "image", do: :image, else: :file

    case Brando.Uploads.validate_intake(type, name, byte_size(body), cfg.size_limit) do
      :ok -> :ok
      {:error, message} -> Error.fail!(message)
    end

    mime = MIME.from_path(name)

    unless "*" in cfg.allowed_mimetypes || mime in cfg.allowed_mimetypes,
      do: Error.fail!("#{name} is not allowed by the destination media configuration.")

    if kind == "image" do
      case Image.from_binary(body) do
        {:ok, image} ->
          if Image.width(image) * Image.height(image) > 100_000_000,
            do: Error.fail!("The image exceeds the 100 megapixel import limit.")

        _ ->
          Error.fail!("#{name} is not a valid image original.")
      end
    end

    %{body: body, cfg: cfg, name: name, mime: mime}
  end

  def stage!(items, files, actor, operation_id) do
    root = Path.join(System.tmp_dir!(), "brando-content-" <> operation_id <> "-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)

    try do
      staged =
        Map.new(items, fn {token, dependency} ->
          validated = validate!(dependency, files, actor)
          path = Path.join(root, Archive.checksum(validated.body))
          File.write!(path, validated.body)
          {token, Map.merge(validated, %{staged: path, dependency: dependency}) |> Map.delete(:body)}
        end)

      %{root: root, items: staged, paths: []}
    rescue
      error ->
        File.rm_rf(root)
        reraise error, __STACKTRACE__
    end
  end

  # Final paths are unique to one reviewed operation. On transaction failure we
  # delete only those exact files, never shared assets or checksum matches.
  def persist!(token, item, actor, operation_id) do
    dependency = item.dependency
    data = dependency["data"]
    kind = dependency["kind"]
    schema = Dependencies.schema!(kind)
    Catalog.authorize!(actor, :create, schema)
    filename = operation_id <> "-" <> String.replace(token, ":", "-") <> Path.extname(item.name)
    relative = Path.join(item.cfg.upload_path, filename)
    path = safe_path!(Brando.Tenant.Storage.current_media_root(), relative)
    File.mkdir_p!(Path.dirname(path))
    File.cp!(item.staged, path)
    Process.put({__MODULE__, :written}, [path | Process.get({__MODULE__, :written}, [])])

    attrs =
      if kind == "image" do
        {:ok, image} = Image.open(path)

        Map.take(data, ~w(title credits alt focal fetchpriority config_target))
        |> Map.merge(%{
          "path" => relative,
          "width" => Image.width(image),
          "height" => Image.height(image),
          "sizes" => %{},
          "formats" => ["original"],
          "status" => "unprocessed",
          "cdn" => false
        })
      else
        Map.take(data, ~w(title config_target))
        |> Map.merge(%{
          "filename" => filename,
          "mime_type" => item.mime,
          "filesize" => File.stat!(path).size,
          "cdn" => false
        })
      end

    attrs = Map.put_new(attrs, "config_target", "default")
    schema |> struct() |> schema.changeset(attrs, actor) |> Repo.insert!()
  end

  def cleanup(stage, committed?) do
    if stage, do: File.rm_rf(stage.root)
    paths = Process.delete({__MODULE__, :written}) || []
    unless committed?, do: Enum.each(paths, &File.rm/1)
    :ok
  end

  def safe_path!(root, relative) when is_binary(relative) do
    if Path.type(relative) != :relative || Enum.any?(Path.split(relative), &(&1 in ["..", "."])) ||
         String.contains?(relative, ["\\", <<0>>]),
       do: Error.fail!("Unsafe media path.")

    root = Path.expand(root)
    path = Path.expand(relative, root)
    unless String.starts_with?(path, root <> "/"), do: Error.fail!("Media path is outside this site's storage.")
    # Check every existing path segment; resolving only the final filename
    # would allow a symlinked upload directory to escape the media root.
    relative
    |> Path.split()
    |> Enum.scan(root, &Path.join(&2, &1))
    |> Enum.each(fn part ->
      case File.lstat(part) do
        {:ok, %{type: :symlink}} -> Error.fail!("Media transfer does not follow symlinks.")
        _ -> :ok
      end
    end)

    path
  end
end
