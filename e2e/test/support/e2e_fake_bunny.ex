defmodule E2EFakeBunny do
  @moduledoc false
  # Bunny Stream for the E2E tests, so a video field configured for Bunny
  # uploads end to end without the network.
  #
  # The API half is this plug, which the E2E config hands to the uploader as
  # `req_options: [plug: E2EFakeBunny]`: creating a video answers with a new
  # guid, and fetching one answers with a finished encode. The tus half is
  # `E2EFakeBunnyTusController`, under `/e2e/bunny/tus`, which the config's
  # `tus_endpoint` points the browser at.
  #
  # The tus uploads in flight are kept here, outside every test's sandbox; the
  # browser's requests carry its sandbox, so the finished upload's webhook
  # reaches the test's video.
  @behaviour Plug

  import Plug.Conn

  @store __MODULE__.Store

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "POST", path_info: ["library", library_id, "videos"]} = conn, _opts) do
    {:ok, body, conn} = read_body(conn)
    title = Jason.decode!(body)["title"]

    json(conn, %{
      "guid" => Ecto.UUID.generate(),
      "videoLibraryId" => String.to_integer(library_id),
      "title" => title
    })
  end

  def call(
        %Plug.Conn{method: "GET", path_info: ["library", library_id, "videos", guid]} = conn,
        _opts
      ) do
    json(conn, %{
      "guid" => guid,
      "videoLibraryId" => String.to_integer(library_id),
      "title" => "Fake Bunny video",
      # Finished
      "status" => 3,
      "length" => 5,
      "width" => 640,
      "height" => 360,
      "availableResolutions" => "360p",
      "thumbnailFileName" => "thumbnail.jpg"
    })
  end

  # The provider library tab lists Bunny's videos; the fake keeps none.
  def call(%Plug.Conn{method: "GET", path_info: ["library", _library_id, "videos"]} = conn, _opts) do
    json(conn, %{"items" => [], "currentPage" => 1, "itemsPerPage" => 24, "totalItems" => 0})
  end

  def call(
        %Plug.Conn{method: "DELETE", path_info: ["library", _library_id, "videos", _guid]} = conn,
        _opts
      ) do
    json(conn, %{"success" => true})
  end

  def call(conn, _opts), do: json(conn, 404, %{"Message" => "Not Found"})

  # The tus uploads in flight, by id: `%{length:, offset:, video_guid:, library_id:}`.
  def put_upload(id, upload), do: Agent.update(store(), &Map.put(&1, id, upload))

  def get_upload(id), do: Agent.get(store(), &Map.get(&1, id))

  def delete_upload(id), do: Agent.update(store(), &Map.delete(&1, id))

  defp json(conn, status \\ 200, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp store do
    case Agent.start(fn -> %{} end, name: @store) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end
end
