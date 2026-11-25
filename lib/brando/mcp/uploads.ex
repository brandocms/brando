defmodule Brando.MCP.Uploads do
  @moduledoc """
  The upload URLs of the MCP endpoint's media tools (`Brando.MCP.Media`): a
  connected tool sends an image's bytes over HTTP, outside the JSON-RPC
  request that `max_request_bytes` caps, to

      PUT /mcp[/<site>/<environment>]/uploads/<upload id>/<secret>

  `prepare/4` makes one for a connection (`brando_media_prepare_upload`).
  The URL is the only credential the PUT needs, so `curl -T photo.jpg <url>`
  works; it is good for one upload, started within `url_minutes`
  (10 by default) of preparing it, by the connection that prepared it while
  that connection is still good, at the same site environment. The secret is
  32 random bytes; only its SHA-256 is kept.

  The bytes are read as they arrive and refused as soon as they pass the
  default image config's size limit, or once their first bytes show they
  are not an image type the config takes (whatever the request's
  `Content-Type` says). A request whose `Content-Type` the endpoint's
  `Plug.Parsers` would read (JSON, forms) is refused (415), as is one sent
  to the URL a second time (409), a URL past its time (410), or a body
  still arriving `transfer_minutes` (10) after it started (408).
  `Brando.MCP.BodyLimit` refuses the parsed types before the parsers read
  them.

  Pending uploads wait in the application's own directory (`root/0`) in
  `upload_dir` (the system's temporary directory by default), one directory
  per upload, readable by the server only: what the prepare call was for, and the bytes once they
  have all arrived. `take/3` (`brando_media_finish_upload`) hands the file
  to the connection that prepared it, once; the directory is removed when
  the upload is finished, and anything not finished within `keep_minutes`
  (60) of preparing it is removed when that connection prepares another upload and
  nightly (`Brando.MCP.prune/0`). A connection has at most `max_pending`
  (10) uploads waiting at once that can still be finished: one whose bytes
  were refused, whose URL passed its time with nothing sent, or whose PUT
  stopped without a word and is past its transfer time, does not count,
  and finishing it removes it.

  The pending directories are on the node that served the request: on more
  than one node, `upload_dir` must be shared between them.
  """

  import Plug.Conn

  alias Brando.Images.Intake
  alias Brando.MCP
  alias Brando.MCP.Grant
  alias Brando.Repo
  alias Brando.Uploads
  alias Brando.Users.User

  require Logger

  @inventory ".pending-by-grant"
  @prepare_error "The upload could not be prepared on the server. Try again."
  @id_bytes 16
  @secret_bytes 32
  # Bandit waits for a whole `read_length` within `read_timeout`, so the
  # pieces are small enough for a slow connection (4 KB a second), and the
  # transfer's deadline is checked after each
  @chunk 64_000
  @read_timeout 15_000
  @meta "meta.json"
  @received "received.json"
  @bytes "bytes"
  @partial "bytes.part"
  @claimed "claimed"
  @taken "taken"
  @failed "failed"

  # Content types the endpoint's `Plug.Parsers` reads: never the bytes of
  # an image, and read before anything here could refuse them
  @parsed_types ["application/json", "application/x-www-form-urlencoded", "multipart/"]

  ## Settings

  defp url_seconds, do: MCP.config(:upload_url_minutes, 10) * 60
  defp transfer_ms, do: MCP.config(:upload_transfer_minutes, 10) * 60_000
  defp keep_seconds, do: MCP.config(:upload_keep_minutes, 60) * 60
  defp max_pending, do: MCP.config(:upload_max_pending, 10)

  @doc """
  The directory pending uploads wait in: the application's own, in
  `upload_dir` or the system's temporary directory. Brando makes it and
  sweeps it; the directory around it is left as it is.
  """
  @spec root() :: Path.t()
  def root do
    base = MCP.config(:upload_dir, nil) || System.tmp_dir!()
    Path.join(base, "brando-mcp-uploads-#{Brando.otp_app() || :brando}")
  end

  # Makes the directory if need be, and checks it as `checked_root/0` does
  defp ensure_root do
    root = root()

    with :ok <- File.mkdir_p(Path.dirname(root)),
         :ok <- mkdir_or_exists(root),
         {:ok, _root} <- checked_root() do
      :ok
    end
  end

  # Nothing is listed, read, written or removed under the directory unless
  # the server has made it its own: not a link, and readable by the server
  # alone. The `chmod` is the check of whose it is, whatever its mode says:
  # it fails on another user's. A refusal is logged once, so an operator can
  # tell why every upload is refused.
  defp checked_root do
    root = root()

    case File.lstat(root) do
      {:ok, %File.Stat{type: :directory}} ->
        if File.chmod(root, 0o700) == :ok,
          do: {:ok, root},
          else: refuse_root(root, "the server cannot make it readable by itself alone")

      {:ok, %File.Stat{type: type}} ->
        refuse_root(root, "it is a #{type}")

      {:error, :enoent} ->
        {:error, :enoent}

      {:error, reason} ->
        refuse_root(root, "it cannot be read (#{reason})")
    end
  end

  defp refuse_root(root, reason) do
    key = {__MODULE__, :refused_root, root, reason}

    unless :persistent_term.get(key, false) do
      :persistent_term.put(key, true)

      Logger.error(
        "[Brando.MCP.Uploads] #{root} is not a directory of the server's own (#{reason}): " <>
          "no upload is prepared, received, finished or swept there. Remove it, or set upload_dir."
      )
    end

    {:error, :refused}
  end

  defp mkdir_or_exists(path) do
    case File.mkdir(path) do
      {:error, :eexist} -> :ok
      result -> result
    end
  end

  @doc "The image config uploads are checked against: `{cfg, size limit, allowed types}`."
  @spec limits() :: {map(), pos_integer(), [String.t()]}
  def limits do
    {cfg, _target} = Uploads.resolve_image_config(nil)
    {cfg, Intake.size_limit(cfg), Intake.allowed_types(cfg)}
  end

  ## Preparing

  @doc """
  Makes an upload URL for the connection `grant` at `tenant`, for an image
  named `filename` going into `folder`. `{:ok, %{upload_id, upload_url,
  expires_at, max_bytes, types}}` or `{:error, message}`.
  """
  @spec prepare(Grant.t(), MCP.tenant(), String.t(), String.t() | nil) :: {:ok, map()} | {:error, String.t()}
  def prepare(%Grant{} = grant, tenant, filename, folder) do
    with :ok <- ensure_root(),
         {:ok, result} <- Repo.transaction(fn -> reserve(grant, tenant, filename, folder) end) do
      result
    else
      _ -> {:error, @prepare_error}
    end
  rescue
    _error in [File.Error, Postgrex.Error, DBConnection.ConnectionError] -> {:error, @prepare_error}
  end

  # All nodes sharing the staging area use the same database. Only another
  # preparation for this grant waits while its inventory is checked and updated.
  defp reserve(grant, tenant, filename, folder) do
    ensure_inventory!()
    lock!("grant-#{grant.id}")
    ensure_directory!(bucket(grant.id))
    with :ok <- room(grant), do: create(grant, tenant, filename, folder)
  end

  defp lock!(key) do
    Ecto.Adapters.SQL.query!(Repo.repo(), "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      "brando-mcp-upload:" <> key
    ])
  end

  defp inventory, do: Path.join(root(), @inventory)
  defp bucket(grant_id) when is_integer(grant_id), do: Path.join(inventory(), Integer.to_string(grant_id))
  defp marker(grant_id, id), do: Path.join(bucket(grant_id), id)

  defp ensure_directory!(path) do
    case File.mkdir(path) do
      :ok ->
        :ok

      {:error, :eexist} ->
        unless match?(%File.Stat{type: :directory}, File.lstat!(path)),
          do: raise(File.Error, reason: :enotdir, action: "use upload inventory", path: path)

      {:error, reason} ->
        raise File.Error, reason: reason, action: "create upload inventory", path: path
    end
  end

  # Existing URLs and their directories keep their names. Adopt uploads
  # prepared before the inventory existed once, before admitting a new one.
  defp ensure_inventory! do
    ensure_directory!(inventory())
    ready = Path.join(inventory(), ".ready")

    unless File.regular?(ready) do
      lock!("inventory")

      unless File.regular?(ready), do: build_inventory!(ready)
    end
  end

  defp build_inventory!(ready) do
    for id <- File.ls!(root()),
        valid_id?(id),
        {:ok, %{"grant_id" => grant_id}} <- [read_meta(id)],
        is_integer(grant_id) do
      track!(grant_id, id)
    end

    File.touch!(ready)
  end

  defp track!(grant_id, id) do
    ensure_directory!(bucket(grant_id))
    File.touch!(marker(grant_id, id))
  end

  defp room(grant) do
    if pending_count(grant.id) >= max_pending(),
      do:
        {:error,
         "This connection has #{max_pending()} uploads waiting to be finished. Finish them with brando_media_finish_upload, or wait until they expire."},
      else: :ok
  end

  defp create(grant, tenant, filename, folder) do
    {_cfg, limit, types} = limits()
    id = random(@id_bytes)
    secret = random(@secret_bytes)
    now = System.system_time(:second)
    expires_at = now + url_seconds()
    dir = dir(id)

    meta = %{
      "grant_id" => grant.id,
      "resource" => MCP.resource(tenant),
      "filename" => filename,
      "folder" => folder,
      "secret_hash" => Base.encode16(:crypto.hash(:sha256, secret), case: :lower),
      "expires_at" => expires_at,
      "keep_until" => now + keep_seconds()
    }

    with :ok <- File.mkdir(dir),
         :ok <- write_reservation(dir, id, meta) do
      {:ok,
       %{
         upload_id: id,
         upload_url: MCP.resource(tenant) <> "/uploads/" <> id <> "/" <> secret,
         expires_at: DateTime.from_unix!(expires_at),
         max_bytes: limit,
         types: types
       }}
    else
      _ -> {:error, @prepare_error}
    end
  end

  defp write_reservation(dir, id, meta) do
    with :ok <- File.chmod(dir, 0o700),
         :ok <- File.write(Path.join(dir, @meta), Jason.encode!(meta)),
         :ok <- File.touch(marker(meta["grant_id"], id)) do
      :ok
    else
      error ->
        File.rm_rf(dir)
        error
    end
  end

  defp random(bytes), do: Base.url_encode64(:crypto.strong_rand_bytes(bytes), padding: false)

  # Only ids this module could have made name a directory: no separators, no
  # dots, so no path outside `root/0`
  defp valid_id?(id), do: is_binary(id) and Regex.match?(~r/\A[A-Za-z0-9_-]{22}\z/, id)

  defp dir(id), do: Path.join(root(), id)

  defp read_meta(id) do
    with true <- valid_id?(id),
         {:ok, _root} <- checked_root(),
         {:ok, json} <- File.read(Path.join(dir(id), @meta)),
         {:ok, %{} = meta} <- Jason.decode(json) do
      {:ok, meta}
    else
      _ -> :error
    end
  end

  # Only uploads that can still be finished hold a place: not one whose
  # bytes were refused, nor a URL past its time that nothing was sent to
  defp pending_count(grant_id) do
    now = System.system_time(:second)

    grant_id
    |> bucket()
    |> File.ls!()
    |> Enum.filter(&valid_id?/1)
    |> Enum.count(fn id ->
      meta = read_meta(id)

      cond do
        stale?(id, meta, now) ->
          with {:ok, _} <- File.rm_rf(dir(id)), do: File.rm(marker(grant_id, id))
          false

        meta == :error and File.lstat(dir(id)) == {:error, :enoent} ->
          File.rm(marker(grant_id, id))
          false

        true ->
          # A stalled or refused upload can still be finished to learn why it
          # failed. Retain its marker so later prepares remove its files at expiry.
          held?(id, meta, grant_id, now)
      end
    end)
  end

  defp held?(id, {:ok, %{"grant_id" => grant_id} = meta}, grant_id, now), do: usable?(id, meta, now)
  # A temporarily unreadable reservation still holds its place.
  defp held?(_id, :error, _, _), do: true
  defp held?(_, _, _, _), do: false

  defp usable?(id, meta, now) do
    dir = dir(id)

    cond do
      File.exists?(Path.join(dir, @failed)) -> false
      File.exists?(Path.join(dir, @bytes)) -> true
      File.exists?(Path.join(dir, @claimed)) -> not stalled?(dir, now)
      true -> not url_expired?(meta, now)
    end
  end

  # A PUT whose process died without a word (Bandit kills an HTTP/2 stream's
  # process when the peer closes; a node can go down) leaves its claim and
  # no bytes: past the transfer's deadline, and the last read's timeout
  # after it, nothing can arrive any more
  defp stalled?(dir, now) do
    not File.exists?(Path.join(dir, @bytes)) and
      case File.stat(Path.join(dir, @claimed), time: :posix) do
        {:ok, %{mtime: claimed_at}} -> claimed_at + div(transfer_ms() + @read_timeout, 1000) < now
        _ -> false
      end
  end

  defp url_expired?(%{"expires_at" => expires_at}, now) when is_integer(expires_at), do: now > expires_at
  defp url_expired?(_meta, _now), do: true

  defp list_ids do
    with {:ok, root} <- checked_root(),
         {:ok, names} <- File.ls(root) do
      Enum.filter(names, &valid_id?/1)
    else
      _ -> []
    end
  end

  @doc """
  Removes the uploads not finished in time, and directories under `root/0`
  without what an upload needs. Returns how many went.
  """
  @spec sweep() :: non_neg_integer()
  def sweep do
    now = System.system_time(:second)

    indexed? =
      match?({:ok, _}, checked_root()) and match?({:ok, %{type: :directory}}, File.lstat(inventory())) and
        File.regular?(Path.join(inventory(), ".ready"))

    count = Enum.count(list_ids(), &sweep_upload(&1, now, indexed?))
    if indexed?, do: sweep_buckets()
    count
  end

  defp sweep_upload(id, now, indexed?) do
    meta = read_meta(id)

    if stale?(id, meta, now) do
      match?({:ok, [_ | _]}, File.rm_rf(dir(id)))
    else
      if indexed?, do: track_missing(id, meta)
      false
    end
  end

  # During a rolling deployment older nodes can still create an upload without
  # a marker. A sweep picks up anything staged since the initial adoption.
  defp track_missing(id, {:ok, %{"grant_id" => grant_id}}) when is_integer(grant_id) do
    unless File.regular?(marker(grant_id, id)) do
      Repo.transaction(fn -> track_existing(grant_id, id) end)
    end
  end

  defp track_missing(_id, _meta), do: :ok

  defp track_existing(grant_id, id) do
    lock!("grant-#{grant_id}")
    if File.dir?(dir(id)), do: track!(grant_id, id)
  end

  # A process may have stopped between removing a directory and its marker.
  # Clean each grant under the prepare lock, including its now-empty bucket.
  defp sweep_buckets do
    for name <- File.ls!(inventory()),
        {id, ""} <- [Integer.parse(name)],
        name == Integer.to_string(id),
        match?({:ok, %{type: :directory}}, File.lstat(bucket(id))) do
      Repo.transaction(fn -> sweep_bucket(id) end)
    end
  end

  defp sweep_bucket(grant_id) do
    lock!("grant-#{grant_id}")
    path = bucket(grant_id)

    with {:ok, names} <- File.ls(path) do
      for id <- names, valid_id?(id), File.lstat(dir(id)) == {:error, :enoent}, do: File.rm(marker(grant_id, id))
      File.rmdir(path)
    end
  end

  defp stale?(_id, {:ok, %{"keep_until" => until}}, now) when is_integer(until), do: until < now
  defp stale?(id, _meta, now), do: older_than?(dir(id), keep_seconds(), now)

  # A directory being made has no meta yet for a moment
  defp older_than?(path, seconds, now) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime + seconds < now
      _ -> false
    end
  end

  ## Receiving

  @doc """
  Answers a request to the upload URL with `id` and `secret` at `tenant`
  (`Brando.MCP.HTTP`).
  """
  @spec accept(Plug.Conn.t(), String.t(), String.t(), MCP.tenant()) :: Plug.Conn.t()
  def accept(conn, id, secret, tenant) do
    with :ok <- put_only(conn),
         {:ok, meta} <- find(id, secret, tenant),
         :ok <- in_time(meta),
         :ok <- connection_good(meta, tenant),
         :ok <- raw_body(conn),
         {_cfg, limit, types} = limits(),
         :ok <- declared_length(conn, limit),
         :ok <- claim(id) do
      receive_bytes(conn, id, limit, types)
    else
      {:error, status, message} -> reply(conn, status, %{error: message})
    end
  end

  defp put_only(%{method: "PUT"}), do: :ok
  defp put_only(_conn), do: {:error, 405, "Send the image's bytes with PUT, for example curl -T photo.jpg <upload_url>."}

  # A wrong secret answers as an unknown upload
  defp find(id, secret, tenant) do
    with {:ok, meta} <- read_meta(id),
         true <- is_binary(secret) and byte_size(secret) <= 100,
         expected when is_binary(expected) <- meta["secret_hash"],
         true <- Plug.Crypto.secure_compare(Base.encode16(:crypto.hash(:sha256, secret), case: :lower), expected),
         true <- meta["resource"] == MCP.resource(tenant) do
      {:ok, meta}
    else
      _ -> {:error, 404, "There is no such upload."}
    end
  end

  defp in_time(%{"expires_at" => expires_at}) when is_integer(expires_at) do
    if System.system_time(:second) <= expires_at,
      do: :ok,
      else: {:error, 410, "This upload URL has expired. Prepare a new upload with brando_media_prepare_upload."}
  end

  defp in_time(_meta), do: {:error, 410, "This upload URL has expired."}

  @doc """
  Whether the connection `grant_id` is still good at `tenant`: not revoked
  or expired, for this site environment, its person still active, allowed to
  connect tools and to add images. `{:ok, grant, user}` or `:error`.
  """
  @spec connection(integer(), MCP.tenant()) :: {:ok, Grant.t(), User.t()} | :error
  def connection(grant_id, tenant) do
    with %Grant{revoked_at: nil} = grant <- Repo.get(Grant, grant_id),
         true <- grant.resource == MCP.resource(tenant),
         false <- MCP.grant_expired?(grant),
         %User{} = user <- Repo.get(User, grant.user_id),
         nil <- MCP.refusal(user, tenant),
         :ok <- may_add_images(user, tenant) do
      {:ok, grant, user}
    else
      _ -> :error
    end
  end

  defp may_add_images(user, tenant) do
    scope = MCP.authorization_scope(user, tenant)

    MCP.in_tenant(tenant, fn ->
      Brando.Authorization.Boundary.with_scope(scope, fn -> Brando.Authorization.Media.authorize(user, :image) end)
    end)
  end

  defp connection_good(%{"grant_id" => grant_id}, tenant) when is_integer(grant_id) do
    case connection(grant_id, tenant) do
      {:ok, _grant, _user} -> :ok
      :error -> {:error, 403, "The connection that prepared this upload may no longer add images."}
    end
  end

  defp connection_good(_meta, _tenant), do: {:error, 404, "There is no such upload."}

  @doc """
  Whether a request's `Content-Type` is one the endpoint's `Plug.Parsers`
  reads (JSON, forms), so never an upload's bytes. Shared with
  `Brando.MCP.BodyLimit`.
  """
  @spec parsed_type?(Plug.Conn.t()) :: boolean()
  def parsed_type?(conn) do
    case get_req_header(conn, "content-type") do
      [] ->
        false

      types ->
        Enum.any?(types, fn type ->
          type = type |> String.trim() |> String.downcase()
          Enum.any?(@parsed_types, &String.starts_with?(type, &1)) or String.contains?(type, "+json")
        end)
    end
  end

  defp raw_body(conn) do
    if parsed_type?(conn),
      do:
        {:error, 415,
         "Send the image's bytes as they are, for example curl -T photo.jpg <upload_url>, not as JSON or a form."},
      else: :ok
  end

  # A declared length over the limit is refused before a byte is read
  defp declared_length(conn, limit) do
    case get_req_header(conn, "content-length") do
      [] ->
        :ok

      [value] ->
        # Not `Brando.MCP.HTTP.parse_length/1`: this module is reached from
        # `Brando.MCP.prune/0`, and the endpoint must not be from there
        case Integer.parse(value) do
          {length, ""} when length > limit -> {:error, 413, too_large(limit)}
          {length, ""} when length >= 0 -> :ok
          _ -> {:error, 400, "The Content-Length is not a number."}
        end

      _ ->
        {:error, 400, "Send one Content-Length."}
    end
  end

  defp too_large(limit), do: "The image is larger than the site takes (#{Brando.Utils.human_size(limit)})."

  # One request gets to send the bytes, even when it fails: a second one
  # needs a new upload URL
  defp claim(id) do
    case File.open(Path.join(dir(id), @claimed), [:write, :exclusive]) do
      {:ok, io} ->
        File.close(io)
        :ok

      {:error, :eexist} ->
        {:error, 409, "This upload URL has been used. Prepare a new upload with brando_media_prepare_upload."}

      {:error, _} ->
        {:error, 404, "There is no such upload."}
    end
  end

  defp receive_bytes(conn, id, limit, types) do
    partial = Path.join(dir(id), @partial)
    deadline = System.monotonic_time(:millisecond) + transfer_ms()

    result =
      case File.open(partial, [:write, :binary, :exclusive]) do
        {:ok, io} ->
          try do
            read_loop(conn, io, %{size: 0, head: "", type: nil, limit: limit, types: types, deadline: deadline})
          rescue
            # Bandit raises when the client goes away or stops sending: the
            # upload is failed before the error goes on to the server
            error ->
              File.close(io)
              mark_failed(id, partial, "The upload was cut off. Prepare a new upload and send it again.")
              reraise error, __STACKTRACE__
          after
            File.close(io)
          end

        {:error, _} ->
          {:error, conn, 500, "The upload could not be written on the server."}
      end

    case result do
      {:ok, conn, %{size: size, type: type, ext: ext}} ->
        received = %{"size" => size, "type" => type, "ext" => ext}

        with :ok <- File.write(Path.join(dir(id), @received), Jason.encode!(received)),
             :ok <- File.rename(partial, Path.join(dir(id), @bytes)) do
          reply(conn, 200, %{
            upload_id: id,
            bytes: size,
            type: type,
            next: "Call brando_media_finish_upload with this upload_id to add the image to the library."
          })
        else
          _ -> failed(conn, id, partial, 500, "The upload could not be written on the server.")
        end

      {:error, conn, status, message} ->
        failed(conn, id, partial, status, message)
    end
  end

  defp failed(conn, id, partial, status, message) do
    mark_failed(id, partial, message)
    conn |> put_resp_header("connection", "close") |> reply(status, %{error: message})
  end

  defp mark_failed(id, partial, message) do
    File.rm(partial)
    File.write(Path.join(dir(id), @failed), message)
  end

  defp read_loop(conn, io, state) do
    if System.monotonic_time(:millisecond) > state.deadline do
      {:error, conn, 408, "The upload took too long. Prepare a new upload and send it again."}
    else
      case read_body(conn, length: @chunk, read_length: @chunk, read_timeout: @read_timeout) do
        {:more, data, conn} -> conn |> chunk(io, data, state, false) |> continue(io)
        {:ok, data, conn} -> chunk(conn, io, data, state, true)
        {:error, :timeout} -> {:error, conn, 408, "The upload stopped arriving. Prepare a new upload and send it again."}
        {:error, _reason} -> {:error, conn, 400, "The upload could not be read. Prepare a new upload and send it again."}
      end
    end
  end

  defp continue({:more, conn, state}, io), do: read_loop(conn, io, state)
  defp continue(result, _io), do: result

  # Each piece is counted before it is written; the type is judged from the
  # first bytes, as soon as there are enough of them
  defp chunk(conn, io, data, state, last?) do
    size = state.size + byte_size(data)
    head = if state.type, do: state.head, else: binary_part_head(state.head <> data)
    state = %{state | size: size, head: head}

    cond do
      size > state.limit ->
        {:error, conn, 413, too_large(state.limit)}

      is_nil(state.type) and (byte_size(head) >= head_bytes() or last?) ->
        case judge(head, state.types, size) do
          {:ok, type, ext} ->
            write_on(conn, io, data, Map.merge(state, %{type: type, ext: ext, head: ""}), last?)

          {:error, status, message} ->
            {:error, conn, status, message}
        end

      true ->
        write_on(conn, io, data, state, last?)
    end
  end

  defp write_on(conn, io, data, state, last?) do
    case IO.binwrite(io, data) do
      :ok when last? -> {:ok, conn, state}
      :ok -> {:more, conn, state}
      _ -> {:error, conn, 500, "The upload could not be written on the server."}
    end
  end

  defp head_bytes, do: Brando.Images.SvgRoot.scan_bytes()
  defp binary_part_head(head), do: binary_part(head, 0, min(byte_size(head), head_bytes()))

  defp judge(_head, _types, 0), do: {:error, 400, "The upload is empty."}

  defp judge(head, types, _size) do
    case Intake.image_type(head, %{allowed_mimetypes: types}) do
      {:ok, type, ext} -> {:ok, type, ext}
      {:error, message} -> {:error, 415, message}
    end
  end

  defp reply(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> then(&if(status == 405, do: put_resp_header(&1, "allow", "PUT"), else: &1))
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end

  ## Finishing

  @doc """
  The bytes of upload `id` for the connection `grant_id` at `tenant`, once:
  `{:ok, %{path, filename, folder, type, ext, dir}}`, or `{:error,
  message}`. `discard/1` removes it once stored.
  """
  @spec take(String.t(), integer(), MCP.tenant()) :: {:ok, map()} | {:error, String.t()}
  def take(id, grant_id, tenant) do
    with {:ok, meta} <- own(id, grant_id, tenant),
         :ok <- arrived(id, meta),
         {:ok, received} <- read_received(id),
         :ok <- take_once(id) do
      {:ok,
       %{
         path: Path.join(dir(id), @bytes),
         filename: meta["filename"],
         folder: meta["folder"],
         type: received["type"],
         ext: received["ext"]
       }}
    end
  end

  # Another connection's upload is as unknown as one that never was
  defp own(id, grant_id, tenant) do
    case read_meta(id) do
      {:ok, %{"grant_id" => ^grant_id} = meta} ->
        cond do
          meta["resource"] != MCP.resource(tenant) -> {:error, unknown()}
          System.system_time(:second) > meta["keep_until"] -> {:error, "This upload has expired. Prepare a new one."}
          true -> {:ok, meta}
        end

      _ ->
        {:error, unknown()}
    end
  end

  defp unknown, do: "There is no such upload for this connection. Prepare one with brando_media_prepare_upload."

  # An upload that can no longer be finished is removed as it is reported
  defp arrived(id, meta) do
    dir = dir(id)

    cond do
      File.exists?(Path.join(dir, @bytes)) ->
        :ok

      File.exists?(Path.join(dir, @failed)) ->
        message = "The upload failed: " <> (Path.join(dir, @failed) |> File.read!() |> String.slice(0, 300))
        discard(id)
        {:error, message <> " Prepare a new upload."}

      stalled?(dir, System.system_time(:second)) ->
        discard(id)
        {:error, "The upload failed: it stopped arriving and never finished. Prepare a new upload."}

      File.exists?(Path.join(dir, @claimed)) ->
        {:error, "The upload is still arriving. Call again once the PUT has answered."}

      url_expired?(meta, System.system_time(:second)) ->
        discard(id)
        {:error, "The upload URL expired before anything was sent to it. Prepare a new upload."}

      true ->
        {:error, "Nothing has been sent to the upload URL yet. Send the image with a PUT to upload_url first."}
    end
  end

  defp read_received(id) do
    with {:ok, json} <- File.read(Path.join(dir(id), @received)),
         {:ok, %{"type" => type, "ext" => ext} = received} when is_binary(type) and is_binary(ext) <-
           Jason.decode(json) do
      {:ok, received}
    else
      _ -> {:error, "The upload could not be read on the server. Prepare a new one."}
    end
  end

  defp take_once(id) do
    case File.open(Path.join(dir(id), @taken), [:write, :exclusive]) do
      {:ok, io} ->
        File.close(io)
        :ok

      _ ->
        {:error, "This upload is being finished already."}
    end
  end

  @doc "Removes upload `id` and its bytes."
  @spec discard(String.t()) :: :ok
  def discard(id) do
    if valid_id?(id) and match?({:ok, _root}, checked_root()), do: File.rm_rf(dir(id))
    :ok
  end
end
