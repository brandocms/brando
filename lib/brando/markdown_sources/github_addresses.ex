defmodule Brando.MarkdownSources.GitHubAddresses do
  @moduledoc false
  # The address ranges GitHub sends webhooks from, the `hooks` list of its
  # `/meta` API, which get the GitHub Markdown webhook's larger budget
  # (`Brando.MarkdownSources.RateLimiter`). Fetched when the node starts and every
  # six hours after, only on a node with connections configured, and never
  # because a request arrived. A failed fetch keeps the last good list and is
  # retried sooner; with no list, no address is GitHub's and every client has the
  # ordinary budget. Configuration (`config :brando, :markdown_sources`):
  #
  #   * `github_meta_url`: another API whose `/meta` has a `hooks` list, such as
  #     GitHub Enterprise Cloud with data residency
  #     (`"https://api.example.ghe.com/meta"`); `nil` fetches nothing
  #   * `github_hook_ranges`: a fixed list of CIDR ranges, used instead of a
  #     fetch, such as the address of a GitHub Enterprise Server, which sends
  #     webhooks from its own
  use GenServer
  require Logger
  alias Brando.ClientIP
  alias Brando.MarkdownSources.Connection

  @default_url "https://api.github.com/meta"
  @refresh :timer.hours(6)
  @retry :timer.minutes(5)
  @max_ranges 1_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Keyword.put(opts, :name, name), name: name)
  end

  def child_spec(opts), do: %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}

  @doc "Whether `address` is in one of GitHub's webhook ranges."
  def member?(address, name \\ __MODULE__)
  def member?(nil, _name), do: false
  def member?(address, name), do: Enum.any?(ranges(name), &ClientIP.in_range?(address, &1))

  @doc "The ranges in use: the configured list, else the last one fetched."
  def ranges(name \\ __MODULE__) do
    case config()[:github_hook_ranges] do
      nil -> :persistent_term.get(key(name), [])
      entries when is_list(entries) -> for entry <- entries, {:ok, range} <- [ClientIP.parse_range(entry)], do: range
      _ -> []
    end
  end

  def init(opts) do
    url = Keyword.get(config(), :github_meta_url, @default_url)

    if is_binary(url) and is_nil(config()[:github_hook_ranges]) and Connection.all() != %{} do
      client = Keyword.get(opts, :client, Brando.MarkdownSources.HTTP)
      {:ok, %{name: opts[:name], client: client, url: url, failures: 0}, {:continue, :fetch}}
    else
      :ignore
    end
  end

  def handle_continue(:fetch, state), do: {:noreply, refresh(state)}
  def handle_info(:fetch, state), do: {:noreply, refresh(state)}
  def handle_info(_, state), do: {:noreply, state}

  defp refresh(state) do
    case fetch(state) do
      {:ok, ranges} ->
        if :persistent_term.get(key(state.name), nil) != ranges, do: :persistent_term.put(key(state.name), ranges)
        Process.send_after(self(), :fetch, @refresh)
        %{state | failures: 0}

      {:error, reason} ->
        Logger.warning(
          "[Brando.MarkdownSources] Could not fetch GitHub's webhook addresses from #{state.url}: #{inspect(reason)}. " <>
            if(:persistent_term.get(key(state.name), nil), do: "Keeping the last list.", else: "No list yet.")
        )

        Process.send_after(self(), :fetch, min(@retry * 2 ** min(state.failures, 10), @refresh))
        %{state | failures: state.failures + 1}
    end
  end

  # Total, so a bad answer cannot restart this process over and over and take
  # Brando's supervisor down with it
  defp fetch(state) do
    with {:ok, %{"hooks" => [_ | _] = hooks}} <- state.client.meta(state.url),
         true <- Enum.count(hooks) <= @max_ranges,
         ranges = Enum.map(hooks, &ClientIP.parse_range/1),
         true <- Enum.all?(ranges, &narrow?/1) do
      {:ok, Enum.map(ranges, &elem(&1, 1))}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_hooks}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  # A range no wider than an IPv4 /8 or IPv6 /16: a broader one would give
  # most of the internet GitHub's budget
  defp narrow?({:ok, {{_, _, _, _}, prefix}}), do: prefix >= 8
  defp narrow?({:ok, {{_, _, _, _, _, _, _, _}, prefix}}), do: prefix >= 16
  defp narrow?(_), do: false

  defp key(name), do: {__MODULE__, name}
  defp config, do: Application.get_env(:brando, :markdown_sources, [])
end
