defmodule Brando.MarkdownSources.HTTP do
  @moduledoc false
  @host "api.github.com"
  @limit 2_000_000

  # Resolve once, reject non-public addresses, and connect to that exact address
  # while retaining GitHub's hostname for SNI and certificate verification.
  def get(path) when is_binary(path) do
    with true <- String.starts_with?(path, "/repos/") and not String.contains?(path, ["\r", "\n"]),
         {:ok, addresses} <- :inet.getaddrs(~c"api.github.com", :inet),
         true <- addresses != [] and Enum.all?(addresses, &public_address?/1),
         {:ok, conn} <-
           Mint.HTTP.connect(:https, hd(addresses), 443,
             hostname: @host,
             mode: :passive,
             protocols: [:http1],
             timeout: 5_000,
             transport_opts: [verify: :verify_peer]
           ) do
      request(conn, path)
    else
      _ -> {:error, :github_unavailable}
    end
  end

  def public_address?({a, b, c, _d}), do: a in 1..223 and a not in [10, 127] and not reserved?(a, b, c)
  def public_address?(_), do: false

  defp reserved?(100, b, _c) when b in 64..127, do: true
  defp reserved?(169, 254, _c), do: true
  defp reserved?(172, b, _c) when b in 16..31, do: true
  defp reserved?(192, 168, _c), do: true
  defp reserved?(192, 0, c) when c in [0, 2], do: true
  defp reserved?(198, b, _c) when b in [18, 19], do: true
  defp reserved?(198, 51, 100), do: true
  defp reserved?(203, 0, 113), do: true
  defp reserved?(_a, _b, _c), do: false

  defp request(conn, path) do
    headers = [
      {"user-agent", "Brando-MarkdownSources"},
      {"accept", "application/vnd.github+json"},
      {"accept-encoding", "identity"},
      {"x-github-api-version", "2022-11-28"}
    ]

    case Mint.HTTP.request(conn, "GET", path, headers, nil) do
      {:ok, conn, ref} ->
        receive_response(conn, ref, %{status: nil, headers: [], body: [], size: 0}, deadline())

      {:error, conn, _} ->
        Mint.HTTP.close(conn)
        {:error, :github_unavailable}
    end
  end

  defp receive_response(conn, ref, state, deadline) do
    case next_response(conn, ref, state, deadline) do
      {:more, conn, state} ->
        receive_response(conn, ref, state, deadline)

      {:halt, conn, result} ->
        Mint.HTTP.close(conn)
        result
    end
  end

  defp next_response(conn, ref, state, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:halt, conn, {:error, :github_timeout}}
    else
      case Mint.HTTP.recv(conn, 0, min(remaining, 5_000)) do
        {:ok, conn, responses} -> consume_responses(conn, responses, ref, state)
        {:error, conn, _, _} -> {:halt, conn, {:error, :github_unavailable}}
      end
    end
  end

  defp consume_responses(conn, responses, ref, state) do
    case consume(responses, ref, state) do
      {:more, state} -> {:more, conn, state}
      {:done, state} -> {:halt, conn, decode(state)}
      {:error, reason} -> {:halt, conn, {:error, reason}}
    end
  end

  defp consume([], _, state), do: {:more, state}
  defp consume([{:status, ref, status} | rest], ref, state), do: consume(rest, ref, %{state | status: status})

  defp consume([{:headers, ref, headers} | rest], ref, state),
    do: consume(rest, ref, %{state | headers: state.headers ++ headers})

  defp consume([{:data, ref, bytes} | rest], ref, state) do
    if state.size + byte_size(bytes) <= @limit,
      do: consume(rest, ref, %{state | size: state.size + byte_size(bytes), body: [bytes | state.body]}),
      else: {:error, :response_too_large}
  end

  defp consume([{:done, ref} | _], ref, state), do: {:done, state}
  defp consume(_, _, _), do: {:error, :invalid_response}

  defp decode(%{status: 200} = state) do
    if Enum.any?(state.headers, fn {key, value} -> key == "content-encoding" and value != "identity" end) do
      {:error, :compressed_response}
    else
      case state.body |> Enum.reverse() |> IO.iodata_to_binary() |> Jason.decode() do
        {:ok, value} when is_map(value) -> {:ok, value}
        _ -> {:error, :invalid_response}
      end
    end
  end

  # Redirects are deliberately not followed. No credentials or user-selected
  # hosts ever reach this client, including through GitHub response URLs.
  defp decode(%{status: 404}), do: {:error, :document_not_found}
  defp decode(%{status: status}) when status in [403, 429], do: {:error, :github_rate_limited}
  defp decode(_), do: {:error, :invalid_response}
  defp deadline, do: System.monotonic_time(:millisecond) + 15_000
end
