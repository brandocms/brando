defmodule Brando.Uploads.Direct do
  @moduledoc """
  Browser-to-bucket uploads for a site's own pages, outside the admin.

  The admin's `BrandoAdmin.UploadManager` runs presign → PUT → finalize for
  editors. A site form that lets its visitors attach files (an application
  portal, a submission form) needs the same transport without an admin user
  or the manager's LiveView. This is that, as three calls:

      # 1. The visitor picked a file. Check it against the field's config and
      #    get a URL the browser can PUT it to.
      {:ok, upload} =
        Brando.Uploads.Direct.presign(:image, "image:MyApp.Entries.Photo:image", %{
          name: "photo.jpg", size: 1_234_567, type: "image/jpeg"
        })

      # upload.ref, upload.upload_url, upload.upload_headers — hand these to
      # the browser, which PUTs the bytes with exactly those headers.

      # 2. The browser says it is done. Check the object and create the row.
      {:ok, image} = Brando.Uploads.Direct.complete(upload.ref)

      # Or it gave up:
      :ok = Brando.Uploads.Direct.cancel(upload.ref)

  The field's config must enable a direct CDN:
  `cdn: %Brando.CDN.Config{enabled: true, direct: true, bucket: …}`. A field
  without one gets `{:ok, :server}` from `presign/4`: the site then accepts
  the bytes itself and stores them with `Brando.Uploads.store_upload/4`.

  Everything `complete/2` trusts was recorded by `presign/4` (a
  `Brando.Uploads.PendingIntent`): the key, the field, the declared size and
  type. The browser only sends the ref back, and the bucket's own metadata
  has to match before a row is created. Images are then processed into their
  sizes in the background; files and videos are ready at once. An intent
  never completed is reaped with its object by
  `Brando.Worker.UploadIntentReaper`.

  Uploads run as `:system` unless `user:` is given. Authorizing *who* may
  upload to the field is the caller's job — this module checks only the
  file. Combine with `hidden_folder` on the field's config to keep visitors'
  files out of the media library.
  """

  alias Brando.Uploads
  alias Brando.Uploads.PendingIntent

  @type asset_type :: :image | :file | :video
  @type file_meta :: %{name: String.t(), size: non_neg_integer(), type: String.t()}
  @type upload :: %{
          ref: Ecto.UUID.t(),
          key: String.t(),
          filename: String.t(),
          upload_url: String.t(),
          upload_headers: map()
        }

  @doc """
  Validate a file against the field's config and presign a PUT for it.

  Returns `{:ok, upload}`, `{:ok, :server}` when the field does not upload
  directly, or `{:error, message}` (wrong type, too large, …) safe to show.

  Options: `:user` (default `:system`), `:folder_id`.
  """
  @spec presign(asset_type, String.t(), file_meta, keyword) ::
          {:ok, upload} | {:ok, :server} | {:error, String.t()}
  def presign(asset_type, config_target, %{name: _, size: _, type: _} = file_meta, opts \\ []) do
    user = Keyword.get(opts, :user, :system)

    case Uploads.initiate(asset_type, config_target, file_meta, user) do
      {:ok, {:direct, direct}} ->
        ref = Ecto.UUID.generate()

        attrs = %{
          ref: ref,
          key: direct.key,
          resolved_target: direct.resolved_target,
          asset_type: asset_type,
          mime_type: file_meta.type,
          filename: file_meta.name,
          filesize: file_meta.size,
          target: %{"folder_id" => Keyword.get(opts, :folder_id)},
          creator_id: user_id(user)
        }

        with {:ok, _intent} <- Uploads.create_pending_intent(attrs) do
          {:ok,
           %{
             ref: ref,
             key: direct.key,
             filename: direct.filename,
             upload_url: direct.upload_url,
             upload_headers: direct.upload_headers
           }}
        end

      {:ok, :server} ->
        {:ok, :server}

      {:error, message} ->
        {:error, message}
    end
  end

  @doc """
  Finish a presigned upload: verify the object against what `presign/4`
  recorded and create its `Image`, `File` or `Video` row.

  An unknown ref (forged, already completed, or reaped) is
  `{:error, :not_found}`. On failure the intent is kept, so a retry can still
  complete it and an abandoned one is still reaped.

  Options: `:user` (default `:system`).
  """
  @spec complete(String.t(), keyword) :: {:ok, struct()} | {:error, term()}
  def complete(ref, opts \\ []) do
    user = Keyword.get(opts, :user, :system)

    case Uploads.get_pending_intent(ref) do
      nil ->
        {:error, :not_found}

      %PendingIntent{} = intent ->
        params = %{
          key: intent.key,
          resolved_target: intent.resolved_target,
          title: intent.filename,
          mime_type: intent.mime_type,
          filesize: intent.filesize,
          folder_id: get_in(intent.target || %{}, ["folder_id"])
        }

        with {:ok, asset} <- Uploads.finalize_direct(intent.asset_type, params, user) do
          Uploads.delete_pending_intent(intent)
          {:ok, asset}
        end
    end
  end

  @doc """
  Abandon a presigned upload: remove its object, if any, and its intent.
  """
  @spec cancel(String.t()) :: :ok
  def cancel(ref) do
    case Uploads.get_pending_intent(ref) do
      nil ->
        :ok

      intent ->
        _ = Uploads.delete_direct_object(intent.asset_type, intent.resolved_target, intent.key)
        Uploads.delete_pending_intent(intent)
        :ok
    end
  end

  defp user_id(%{id: id}), do: id
  defp user_id(_system), do: nil
end
