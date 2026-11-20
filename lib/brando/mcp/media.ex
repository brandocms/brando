defmodule Brando.MCP.Media do
  @moduledoc """
  The media tools the remote MCP endpoint offers (`Brando.MCP.Tools`, as
  `brando_media_…`): add an image to the media library from a file the
  client has, or from a public `https` URL, for a proposal to use.

  A file comes in two steps, as a client cannot put a file of any size in a
  JSON argument: `prepare_upload` gives a one-time upload URL
  (`Brando.MCP.Uploads`), the client sends the bytes there with a PUT, and
  `finish_upload` stores them. `import_url` downloads an image through
  `Brando.Webhooks.URLGuard` instead. Both store it as an editor's upload is
  stored (`Brando.Images.Intake`), reuse an image the library already has
  of the same bytes, and return its asset (`{"kind": "image", "id": N}`).
  Like the Figma import, the image is added at once, before any proposal is
  applied; its sizes are made in the background.

  They run as the connection's person, in its site environment and
  authorization scope, who needs the right to add images. Only images so
  far: `kind` is an argument so files and videos can follow.
  """

  alias Brando.Content.Transfer.Catalog
  alias Brando.Images
  alias Brando.Images.Image
  alias Brando.Images.Intake
  alias Brando.MCP.Uploads
  alias Brando.Uploads.ContentType

  import Ecto.Query, only: [from: 2]

  require Logger

  @prefix "brando_media_"
  @default_folder "uploads"
  @download_timeout 60_000
  @text_limit 1_000

  @focal %{
    description:
      ~s[The image's focal point: {"x": 0–100, "y": 0–100, "mode": "center" or "position"} (percent from the top left; "center" keeps the point in every crop, "position" lines crops up like CSS object-position), ] <>
        ~s[or {"from": {"kind": "image", "id": N}} to copy the focal point of library image N, such as the image this one replaces.],
    type: "object"
  }

  @texts %{
    title: %{
      type: "string",
      description: "The image's title (caption), in the site's default language."
    },
    alt: %{
      type: "string",
      description: "The image's alt text, in the site's default language: what it shows, for people who cannot see it."
    }
  }

  @stored ~s[Returns the image's asset for brando_content_prepare_proposal ({"kind":"image","id":N}), whether the library already had it (reused), and what of focal, title and alt was applied and not_applied. ] <>
            "An image the library already has (the same bytes) is reused and keeps its own focal point and texts. " <>
            "The image is added to the library at once, before any proposal is applied; its sizes are made in the background."

  @definitions [
    %{
      name: "prepare_upload",
      description:
        "Prepare to upload a file from your side to this site's media library: returns an upload_url to send the file's bytes to with a PUT " <>
          "(for example curl -T photo.jpg '<upload_url>'), an upload_id for brando_media_finish_upload, when the URL expires (minutes), the most bytes it takes and the image types the site takes. " <>
          "The URL works once, for this connection; it needs no other credentials, so do not share it. The type is read from the file's bytes. " <>
          "Then call brando_media_finish_upload with the upload_id to add the image. Only images (kind \"image\") so far.",
      parameters: %{
        type: "object",
        properties: %{
          kind: %{type: "string", enum: ["image"], description: "What is uploaded: \"image\" (the only kind so far)."},
          filename: %{
            type: "string",
            description: "The file's name, which names the stored image (its extension follows the file's type)."
          },
          folder: %{
            type: "string",
            description:
              "The library folder to put it in, as a path (from brando_content_find_media_folders, or new). Without it, \"#{@default_folder}\"."
          }
        },
        required: ["kind", "filename"]
      },
      read_only: false,
      idempotent: false,
      open_world: false
    },
    %{
      name: "finish_upload",
      description:
        "Add the file sent to a brando_media_prepare_upload URL to the media library, as an editor's upload is added, checked against the site's image types and size limit. " <>
          @stored,
      parameters: %{
        type: "object",
        properties:
          Map.merge(@texts, %{
            upload_id: %{type: "string", description: "upload_id from brando_media_prepare_upload."},
            focal: @focal
          }),
        required: ["upload_id"]
      },
      read_only: false,
      idempotent: false,
      open_world: false
    },
    %{
      name: "import_url",
      description:
        "Import an image from a public https address into this site's media library, as an editor's upload is added, checked against the site's image types and size limit. " <>
          "The address must answer with the image itself: redirects are not followed, and private or local addresses are refused. " <>
          @stored,
      parameters: %{
        type: "object",
        properties:
          Map.merge(@texts, %{
            url: %{type: "string", description: "The image's https address."},
            filename: %{
              type: "string",
              description: "A name for the stored image. Without it, the last part of the address's path."
            },
            folder: %{
              type: "string",
              description:
                "The library folder to put it in, as a path (from brando_content_find_media_folders, or new). Without it, \"#{@default_folder}\"."
            },
            focal: @focal
          }),
        required: ["url"]
      },
      read_only: false,
      idempotent: true,
      open_world: true
    }
  ]

  @names Enum.map(@definitions, & &1.name)

  @doc "The prefix of these tools' names over MCP."
  @spec prefix() :: String.t()
  def prefix, do: @prefix

  @doc "The tools' names, without the prefix."
  @spec names() :: [String.t()]
  def names, do: @names

  @doc "The tool definitions: name (without the prefix), description, parameters and hints."
  @spec definitions() :: [map()]
  def definitions, do: @definitions

  @doc """
  Runs tool `name` with `args` for the connection in `auth`
  (`Brando.MCP.OAuth.authenticate/2`) at `tenant`, already in its schema
  prefix and authorization scope. `{:ok, result}` or `{:error, message}`.
  """
  @spec call(String.t(), map(), map(), Brando.MCP.tenant()) :: {:ok, map()} | {:error, String.t()}
  def call(name, args, auth, tenant) when name in @names do
    with :ok <- Brando.Authorization.Media.authorize(auth.user, :image) do
      run(name, args, auth, tenant)
    end
  end

  defp run("prepare_upload", args, %{grant: grant}, tenant) do
    with :ok <- kind(args["kind"]),
         {:ok, filename} <- text(args["filename"], "filename", 255, required: true),
         {:ok, folder} <- folder(args["folder"]) do
      Uploads.prepare(grant, tenant, filename, folder)
    end
  end

  defp run("finish_upload", args, %{grant: grant, user: actor}, tenant) do
    with {:ok, id} <- text(args["upload_id"], "upload_id", 100, required: true),
         {:ok, attrs} <- attributes(args, actor),
         {:ok, upload} <- Uploads.take(id, grant.id, tenant) do
      try do
        ctx = Intake.context(actor, upload.folder)
        name = Path.rootname(upload.filename)

        upload.path
        |> Intake.store(Intake.filename(name, upload.ext, "upload"), upload.type, ctx, &put_attributes(&1, attrs, actor))
        |> result(ctx, attrs)
      after
        Uploads.discard(id)
      end
    end
  end

  defp run("import_url", args, %{user: actor}, _tenant) do
    with {:ok, url} <- text(args["url"], "url", 2_048, required: true),
         {:ok, filename} <- text(args["filename"], "filename", 255),
         {:ok, folder} <- folder(args["folder"]),
         {:ok, attrs} <- attributes(args, actor) do
      ctx = Intake.context(actor, folder)
      import_url(url, filename || url_name(url), ctx, attrs)
    end
  end

  defp kind("image"), do: :ok

  defp kind(other) when other in ["file", "video"],
    do:
      {:error,
       "Only images can be uploaded so far (kind \"image\"); #{other}s cannot. Ask the person to add it in the media library."}

  defp kind(_other), do: {:error, "kind is \"image\": only images can be uploaded so far."}

  defp text(value, name, max, opts \\ [])
  defp text(nil, name, _max, opts), do: if(opts[:required], do: {:error, "#{name} is required."}, else: {:ok, nil})

  defp text(value, name, max, opts) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" and opts[:required] -> {:error, "#{name} is required."}
      value == "" -> {:ok, nil}
      String.length(value) > max -> {:error, "#{name} is at most #{max} characters."}
      true -> {:ok, value}
    end
  end

  defp text(_value, name, _max, _opts), do: {:error, "#{name} is a string."}

  defp folder(value) do
    with {:ok, folder} <- text(value, "folder", 200) do
      case folder && BrandoAdmin.Images.FolderBrowser.normalize_folder(folder) do
        nil -> {:ok, @default_folder}
        folder -> {:ok, folder}
      end
    end
  end

  # The last part of the address's path, without its query
  defp url_name(url) do
    case URI.parse(url) do
      %URI{path: path} when is_binary(path) -> path |> Path.basename() |> URI.decode()
      _ -> nil
    end
  rescue
    _ -> nil
  end

  ## Focal point, title and alt text

  # Checked before anything is stored or downloaded
  defp attributes(args, actor) do
    with {:ok, focal} <- focal(args["focal"], actor),
         {:ok, title} <- text(args["title"], "title", @text_limit),
         {:ok, alt} <- text(args["alt"], "alt", @text_limit) do
      {:ok, %{focal: focal, title: title, alt: alt} |> Map.reject(fn {_key, value} -> is_nil(value) end)}
    end
  end

  defp focal(nil, _actor), do: {:ok, nil}

  defp focal(%{"from" => %{"kind" => "image", "id" => id}}, actor) when is_integer(id) do
    query = from(i in Image, where: i.id == ^id and is_nil(i.deleted_at))

    case query |> Catalog.scoped_query(Image, actor, :read) |> Brando.Repo.one() do
      %Image{focal: %{x: x, y: y} = focal} -> {:ok, %{x: x, y: y, mode: Images.Focal.mode(focal)}}
      %Image{} -> {:ok, %{x: 50, y: 50, mode: :center}}
      nil -> {:error, "focal.from: there is no image #{id} you may read."}
    end
  end

  defp focal(%{"from" => _from}, _actor),
    do: {:error, ~s[focal.from is an image's asset: {"kind": "image", "id": N}.]}

  defp focal(%{"x" => x, "y" => y} = focal, _actor) when is_number(x) and is_number(y) do
    with :ok <- percent(x, "x"),
         :ok <- percent(y, "y"),
         {:ok, mode} <- mode(focal["mode"]) do
      {:ok, %{x: round(x), y: round(y), mode: mode}}
    end
  end

  defp focal(_focal, _actor),
    do:
      {:error,
       ~s[focal is {"x": 0–100, "y": 0–100, "mode": "center" or "position"}, or {"from": {"kind": "image", "id": N}}.]}

  defp percent(value, _name) when value >= 0 and value <= 100, do: :ok
  defp percent(_value, name), do: {:error, "focal.#{name} is a percentage, from 0 to 100."}

  defp mode(nil), do: {:ok, :center}
  defp mode("center"), do: {:ok, :center}
  defp mode("position"), do: {:ok, :position}
  defp mode(_mode), do: {:error, ~s[focal.mode is "center" or "position".]}

  # A new image gets them, inside the store's lock; one the library has
  # keeps its own (an editor may have set them)
  defp put_attributes(image, attrs, _actor) when attrs == %{}, do: {:stored, image}

  defp put_attributes(image, attrs, actor) do
    case Images.update_image(image, attrs, actor) do
      {:ok, image} ->
        {:stored, image, :applied}

      error ->
        Logger.warning(
          "[Brando.MCP.Media] Could not set the focal point and texts of image #{image.id}: #{inspect(error)}"
        )

        {:stored, image, :failed}
    end
  end

  defp result({:error, message}, _ctx, _attrs), do: {:error, message}

  defp result(stored, ctx, attrs) do
    {image, reused, outcome} =
      case stored do
        {:stored, image} -> {image, false, :applied}
        {:stored, image, outcome} -> {image, false, outcome}
        {:reused, image} -> {image, true, :reused}
      end

    named = attrs |> Map.keys() |> Enum.sort() |> Enum.map(&Atom.to_string/1)

    {applied, not_applied} =
      case {outcome, named} do
        {_outcome, []} ->
          {[], []}

        {:applied, named} ->
          {named, []}

        {:reused, named} ->
          {[], Enum.map(named, &(&1 <> ": the library already had this image, so it keeps its own"))}

        {:failed, named} ->
          {[], Enum.map(named, &(&1 <> ": it could not be saved; the person can set it in the media library"))}
      end

    {:ok,
     %{
       asset: %{kind: "image", id: image.id},
       reused: reused,
       folder: ctx.folder,
       applied: applied,
       not_applied: not_applied
     }
     |> Map.reject(fn {_key, value} -> value in [[], nil] end)}
  end

  ## Importing from a URL

  defp import_url(url, name, ctx, attrs) do
    dir = Path.join(System.tmp_dir!(), "brando-mcp-import-" <> Base.url_encode64(:crypto.strong_rand_bytes(9)))
    File.mkdir_p!(dir)
    path = Path.join(dir, "download")

    try do
      with {:ok, path} <-
             Intake.download(url, path, Intake.size_limit(ctx.cfg), timeout: @download_timeout, who: "The address"),
           {:ok, head} <- ContentType.head(path),
           {:ok, type, ext} <- Intake.image_type(head, ctx.cfg) do
        name = name && Path.rootname(name)

        path
        |> Intake.store(Intake.filename(name, ext, "image"), type, ctx, &put_attributes(&1, attrs, ctx.actor))
        |> result(ctx, attrs)
      else
        {:error, message} when is_binary(message) -> {:error, message}
        _ -> {:error, "The download could not be read."}
      end
    after
      File.rm_rf(dir)
    end
  end
end
