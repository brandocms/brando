defmodule Brando.Cache.Freshness do
  @moduledoc false
  # Which writes this node's render inputs have caught up with, for the entry
  # render jobs, which any node may run (`Brando.Cache.ensure_fresh/1`).
  #
  # The render inputs are the site caches the renders read and the query
  # cache sources they list. A node that refreshes one for a write makes a
  # token: its latest for the input, known once the refresh has run. Every
  # render job it queues carries its latest tokens, and a node that does not
  # know one refreshes the input before it renders, and then knows it. A
  # token a node learns from a job is not its latest: its own latest may
  # stand for a write the token's maker never saw.
  #
  # A token made inside a transaction (`Brando.Repo.transaction/2`) is the
  # transaction's until it commits: the jobs it queues carry it, and it
  # becomes the node's latest once committed. Before that, a node that ran a
  # job carrying it would refresh from rows still without the write, and
  # then skip the refresh the commit sends. Rolled back, it is gone. One
  # transaction makes one token per input, however often it writes it.
  #
  # Kept per site, for each input, as `%{latest: token, known: [token]}`;
  # a transaction's as `%{site_key => %{input => token}}`.
  #
  # A job carries one token per input, or a list once renders queued for the
  # same entry coalesced into it (`merge/2`): tokens from different nodes, or
  # from either side of a commit, have no order, so the job keeps them all.

  alias Brando.Repo
  alias Brando.Tenant

  @cache_module Application.compile_env(:brando, :cache_module, Cachex)
  @key {__MODULE__, :tokens}
  @pending {__MODULE__, :pending}
  @known 32
  # Tokens one coalesced job keeps per input, the newest
  @carried 16
  @site_caches ~w(identity globals navigation)a
  @render_schemas [
    Module.concat(["Brando", "Content", "Module"]),
    Module.concat(["Brando", "Content", "Container"]),
    Module.concat(["Brando", "Content", "Palette"]),
    Module.concat(["Brando", "Pages", "Fragment"])
  ]

  @type input :: {:site_cache, atom()} | {:query_source, String.t()}

  @doc "The render input a site cache or query cache source is, or nil."
  @spec input(:site_cache, atom()) :: input() | nil
  @spec input(:query_source, String.t()) :: input() | nil
  def input(:site_cache, cache), do: if(cache in @site_caches, do: {:site_cache, cache})
  def input(:query_source, source), do: if(source in sources(), do: {:query_source, source})

  @doc """
  Makes a token for a refresh of `input` about to run: this node's latest,
  at once outside a transaction, once it commits inside one.
  """
  @spec make(input()) :: String.t()
  def make(input) do
    site = Tenant.cache_key(@key)
    pending = Repo.transaction_value(@pending) || %{}

    case pending do
      %{^site => %{^input => token}} ->
        token

      _ ->
        token = Base.url_encode64(:crypto.strong_rand_bytes(9))
        pending = Map.update(pending, site, %{input => token}, &Map.put(&1, input, token))
        hold_or_publish(Repo.put_transaction_value(@pending, pending), site, input, token)
        token
    end
  end

  defp hold_or_publish(:ok, site, input, token),
    do: Repo.after_commit({__MODULE__, site, input}, fn -> publish(site, input, token) end)

  defp hold_or_publish(:error, site, input, token), do: publish(site, input, token)

  defp publish(site, input, token) do
    update(site, &Map.update(&1, input, %{latest: token, known: []}, fn record -> %{record | latest: token} end))
  end

  @doc "Records that this node's copy of `input` has caught up with `token`."
  @spec known(input(), String.t()) :: :ok
  def known(input, token) do
    update(Tenant.cache_key(@key), fn tokens ->
      Map.update(tokens, input, %{latest: nil, known: [token]}, fn record ->
        %{record | known: Enum.take([token | List.delete(record.known, token)], @known)}
      end)
    end)

    :ok
  end

  @doc """
  Adds this node's latest tokens to a render job's arguments, and inside a
  transaction those it made, in their place.
  """
  @spec attach(map()) :: map()
  def attach(args) do
    latest = for {input, %{latest: token}} <- tokens(), token, into: %{}, do: {input, token}
    pending = Map.get(Repo.transaction_value(@pending) || %{}, Tenant.cache_key(@key), %{})
    tokens = latest |> Map.merge(pending) |> Map.to_list()

    args
    |> put_latest("site_caches", for({{:site_cache, cache}, t} <- tokens, do: {to_string(cache), t}))
    |> put_latest("query_sources", for({{:query_source, source}, t} <- tokens, do: {source, t}))
  end

  defp put_latest(args, _field, []), do: args
  defp put_latest(args, field, latest), do: Map.put(args, field, Map.new(latest))

  @doc """
  The arguments of a queued render job, `args`, with the tokens of another
  render queued for the same entry (`more`) added: a render that runs once
  for both refreshes what either needs.
  """
  @spec merge(map(), map()) :: map()
  def merge(args, more) do
    Enum.reduce(~w(site_caches query_sources), args, fn field, args ->
      tokens = Map.merge(Map.get(args, field) || %{}, Map.get(more, field) || %{}, fn _, a, b -> union(a, b) end)
      if tokens == %{}, do: args, else: Map.put(args, field, tokens)
    end)
  end

  defp union(a, b) do
    case Enum.uniq(List.wrap(a) ++ List.wrap(b)) do
      [token] -> token
      tokens -> Enum.take(tokens, -@carried)
    end
  end

  @doc "The inputs and tokens in a render job's arguments this node does not know."
  @spec unknown(map()) :: [{input(), String.t()}]
  def unknown(args) do
    tokens = tokens()

    for {input, token} <- carried(args), input, not known?(tokens[input], token), do: {input, token}
  end

  defp known?(%{known: known}, token), do: token in known
  defp known?(nil, _token), do: false

  defp carried(args) do
    site_caches =
      for {name, tokens} <- Map.get(args, "site_caches") || %{}, token <- List.wrap(tokens), do: {site_cache(name), token}

    sources =
      for {source, tokens} <- Map.get(args, "query_sources") || %{},
          token <- List.wrap(tokens),
          do: {input(:query_source, source), token}

    site_caches ++ sources
  end

  defp site_cache(name), do: Enum.find_value(@site_caches, &(to_string(&1) == name && {:site_cache, &1}))

  defp sources, do: Enum.map(@render_schemas, & &1.__schema__(:source))

  defp tokens do
    case @cache_module.get(:cache, Tenant.cache_key(@key)) do
      {:ok, tokens} when is_map(tokens) -> tokens
      _ -> %{}
    end
  end

  defp update(site, fun), do: @cache_module.get_and_update(:cache, site, &fun.(&1 || %{}))
end
