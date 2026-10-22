defmodule E2EFakeBunnyTusController do
  @moduledoc false
  # Bunny's tus endpoint for the E2E tests (see `E2EFakeBunny`): it takes an
  # upload as Bunny does, discards the bytes, and once the last one is in
  # reports the encode finished through Brando's own webhook handling, so the
  # video is ready when the browser learns the upload is done.
  use E2eProjectWeb, :controller

  alias Brando.Videos.Uploaders.Bunny

  # Bunny's "Finished" webhook status
  @finished 3

  def create(conn, _params) do
    with {:ok, video_guid, library_id} <- authorize(conn),
         [length] <- get_req_header(conn, "upload-length") do
      id = Ecto.UUID.generate()

      E2EFakeBunny.put_upload(id, %{
        length: String.to_integer(length),
        offset: 0,
        video_guid: video_guid,
        library_id: library_id
      })

      conn
      |> tus_headers()
      |> put_resp_header("location", "/e2e/bunny/tus/#{id}")
      |> send_resp(201, "")
    else
      _ -> send_resp(conn, 401, "")
    end
  end

  # HEAD, which Plug.Head turns into a GET: how far an upload has got.
  def show(conn, %{"id" => id}) do
    case E2EFakeBunny.get_upload(id) do
      %{length: length, offset: offset} ->
        conn
        |> tus_headers()
        |> put_resp_header("upload-offset", to_string(offset))
        |> put_resp_header("upload-length", to_string(length))
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(200, "")

      nil ->
        send_resp(conn, 404, "")
    end
  end

  def update(conn, %{"id" => id}) do
    with %{offset: offset} = upload <- E2EFakeBunny.get_upload(id),
         [^offset] <- conn |> get_req_header("upload-offset") |> Enum.map(&String.to_integer/1),
         {:ok, received, conn} <- discard_body(conn, 0) do
      offset = offset + received
      E2EFakeBunny.put_upload(id, %{upload | offset: offset})
      if offset >= upload.length, do: finish(id, upload)

      conn
      |> tus_headers()
      |> put_resp_header("upload-offset", to_string(offset))
      |> send_resp(204, "")
    else
      nil -> send_resp(conn, 404, "")
      _ -> send_resp(conn, 409, "")
    end
  end

  defp finish(id, %{video_guid: video_guid, library_id: library_id}) do
    E2EFakeBunny.delete_upload(id)

    {:ok, _video} =
      Bunny.handle_webhook(%{
        "VideoLibraryId" => library_id,
        "VideoGuid" => video_guid,
        "Status" => @finished
      })
  end

  # The signature Bunny checks: SHA256(library_id <> api_key <> expire <> video_id).
  defp authorize(conn) do
    config = Application.get_env(:brando, Bunny)

    with [signature] <- get_req_header(conn, "authorizationsignature"),
         [expire] <- get_req_header(conn, "authorizationexpire"),
         [video_guid] <- get_req_header(conn, "videoid"),
         [library_id] <- get_req_header(conn, "libraryid"),
         expected =
           :sha256
           |> :crypto.hash("#{library_id}#{config[:api_key]}#{expire}#{video_guid}")
           |> Base.encode16(case: :lower),
         true <- Plug.Crypto.secure_compare(signature, expected) do
      {:ok, video_guid, library_id}
    end
  end

  defp discard_body(conn, received) do
    case read_body(conn) do
      {:ok, chunk, conn} -> {:ok, received + byte_size(chunk), conn}
      {:more, chunk, conn} -> discard_body(conn, received + byte_size(chunk))
      error -> error
    end
  end

  defp tus_headers(conn), do: put_resp_header(conn, "tus-resumable", "1.0.0")
end
