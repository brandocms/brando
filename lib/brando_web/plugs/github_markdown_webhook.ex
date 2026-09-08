defmodule BrandoWeb.Plugs.GitHubMarkdownWebhook do
  @moduledoc """
  Receives authenticated Markdown refresh signals. Mount before Plug.Parsers:

      plug BrandoWeb.Plugs.GitHubMarkdownWebhook

  Endpoint: POST /api/markdown-sources/webhooks/:connection
  Connections and allowed destinations are server-owned configuration.
  """
  import Plug.Conn
  alias Brando.MarkdownSources.{Connection, Delivery, RateLimiter}
  alias Brando.Repo
  @max_body 1_048_576

  def init(opts), do: opts

  def call(conn, opts) do
    mount = Keyword.get(opts, :mount, ["api", "markdown-sources", "webhooks"])

    case Enum.split(conn.path_info, length(mount)) do
      {^mount, [key]} -> handle(conn, key, opts)
      _ -> conn
    end
  end

  defp handle(conn, key, opts) do
    with true <- conn.scheme == :https or Keyword.get(opts, :allow_insecure, false),
         true <- conn.method == "POST",
         true <- RateLimiter.allow?(conn.remote_ip),
         {:ok, connection} <- Connection.get(key),
         [content_type] <- get_req_header(conn, "content-type"),
         true <- String.downcase(hd(String.split(content_type, ";"))) == "application/json",
         {:ok, body, conn} <- body(conn, [], 0, System.monotonic_time(:millisecond) + 10_000) do
      authenticate_and_accept(conn, connection, body)
    else
      {:error, :too_large, conn} -> respond(conn, 413, "request_too_large")
      {:error, :incomplete_body, conn} -> respond(conn, 400, "incomplete_body")
      _ -> respond(conn, 401, "delivery_rejected")
    end
  end

  defp authenticate_and_accept(conn, connection, body) do
    with :ok <- verify(get_req_header(conn, "x-hub-signature-256"), body, connection.secret),
         {:ok, payload} when is_map(payload) <- Jason.decode(body),
         :ok <- repository(payload, connection),
         {:ok, event} <- event(get_req_header(conn, "x-github-event"), payload),
         {:ok, delivery_id} <- delivery_id(get_req_header(conn, "x-github-delivery")),
         {:ok, _} <- accept(connection, event, payload, body, delivery_id) do
      respond(conn, 202, "accepted")
    else
      {:error, :persistence_failed} -> respond(conn, 503, "temporarily_unavailable")
      _ -> respond(conn, 401, "delivery_rejected")
    end
  end

  def verify(["sha256=" <> hex], body, secret)
      when is_binary(secret) and byte_size(secret) >= 32 and byte_size(hex) == 64 do
    with {:ok, signature} <- Base.decode16(hex, case: :mixed),
         expected <- :crypto.mac(:hmac, :sha256, secret, body),
         true <- Plug.Crypto.secure_compare(expected, signature),
         do: :ok,
         else: (_ -> {:error, :invalid_signature})
  end

  def verify(_, _, _), do: {:error, :invalid_signature}

  defp body(conn, chunks, size, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :incomplete_body, conn}
    else
      case read_body(conn,
             length: min(64_000, @max_body - size + 1),
             read_length: 64_000,
             read_timeout: min(remaining, 5_000)
           ) do
        {status, bytes, conn} when status in [:ok, :more] ->
          cond do
            size + byte_size(bytes) > @max_body -> {:error, :too_large, conn}
            status == :more -> body(conn, [bytes | chunks], size + byte_size(bytes), deadline)
            true -> {:ok, IO.iodata_to_binary(Enum.reverse([bytes | chunks])), conn}
          end

        _ ->
          {:error, :incomplete_body, conn}
      end
    end
  end

  defp repository(%{"repository" => %{"id" => id}}, %{repository_id: id}), do: :ok
  defp repository(_, _), do: {:error, :wrong_repository}
  defp event(["ping"], %{"zen" => zen}) when is_binary(zen), do: {:ok, :ping}

  defp event(["push"], %{"ref" => "refs/heads/" <> _ = ref, "after" => sha, "deleted" => deleted})
       when is_binary(sha) and is_boolean(deleted) do
    if byte_size(ref) <= 256 and Regex.match?(~r/\A[0-9a-f]{40}\z/, sha), do: {:ok, :push}, else: {:error, :invalid_event}
  end

  defp event(_, _), do: {:error, :invalid_event}

  defp delivery_id([id]) do
    if Regex.match?(~r/\A[a-zA-Z0-9-]{16,80}\z/, id), do: {:ok, id}, else: {:error, :invalid_delivery}
  end

  defp delivery_id(_), do: {:error, :invalid_delivery}

  defp accept(_, :ping, _, _, _), do: {:ok, :ping}

  defp accept(connection, :push, payload, body, delivery_id) do
    fingerprint = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

    Repo.transaction(fn ->
      receipt = %Delivery{connection: connection.key, delivery_id: delivery_id, fingerprint: fingerprint}

      case Repo.insert(receipt, on_conflict: :nothing) do
        {:ok, %{id: nil}} ->
          :duplicate

        {:ok, receipt} ->
          job_ids =
            Enum.flat_map(connection.destinations, fn prefix ->
              case Connection.destination(connection, prefix) do
                {:ok, _} ->
                  Brando.Tenant.with_prefix(prefix, fn ->
                    args = %{
                      connection: connection.key,
                      ref: payload["ref"],
                      generation: Connection.generation(connection)
                    }

                    case args |> Brando.Tenant.Job.attach() |> Brando.Worker.MarkdownSourceSync.new() |> Oban.insert() do
                      {:ok, job} -> if(job.id, do: [job.id], else: [])
                      _ -> Repo.rollback(:persistence_failed)
                    end
                  end)

                _ ->
                  []
              end
            end)

          receipt |> Ecto.Changeset.change(job_ids: job_ids) |> Repo.update!()
          :accepted

        _ ->
          Repo.rollback(:persistence_failed)
      end
    end)
  rescue
    _ -> {:error, :persistence_failed}
  end

  defp respond(conn, status, message),
    do:
      conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(%{status: message})) |> halt()
end
