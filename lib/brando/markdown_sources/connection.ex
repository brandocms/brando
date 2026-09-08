defmodule Brando.MarkdownSources.Connection do
  @moduledoc "Server-owned GitHub connections and explicit environment authorization."
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  def all, do: Application.get_env(:brando, :markdown_sources, []) |> Keyword.get(:connections, %{})

  def get(key) when is_binary(key) do
    case Map.get(all(), key) do
      %{repository: repo, repository_id: id, secret: secret, destinations: destinations} = connection
      when is_binary(repo) and is_integer(id) and id > 0 and is_binary(secret) and
             byte_size(secret) >= 32 and is_list(destinations) and length(destinations) in 1..16 ->
        if Map.get(connection, :enabled, true) and Regex.match?(~r/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/, repo),
          do: {:ok, Map.put(connection, :key, key)},
          else: {:error, :connection_disabled}

      _ ->
        {:error, :connection_disabled}
    end
  end

  def get(_), do: {:error, :connection_disabled}

  def available do
    all()
    |> Map.keys()
    |> Enum.sort()
    |> Enum.filter(fn key -> match?({:ok, _}, current(key)) end)
  end

  def current(key) do
    with {:ok, connection} <- get(key),
         {:ok, destination} <- destination(connection, Tenant.current_prefix()) do
      {:ok, Map.put(connection, :destination, destination)}
    end
  end

  def destination(connection, prefix) do
    with true <- prefix in connection.destinations do
      resolve_destination(prefix)
    else
      _ -> {:error, :destination_forbidden}
    end
  end

  defp resolve_destination(nil) do
    if Tenant.mode() == :none, do: {:ok, %{site: nil, environment: nil}}, else: {:error, :destination_forbidden}
  end

  defp resolve_destination("tenant_" <> suffix = prefix) do
    with true <- Tenant.enabled?() and Tenant.valid_prefix?(prefix),
         [site_key, environment_key] <- String.split(suffix, "_", parts: 2),
         %{status: :active} = site <- Registry.get_site_by_key(site_key),
         environment when not is_nil(environment) <- Registry.get_environment_by_key(site, environment_key) do
      {:ok, %{site: site, environment: environment}}
    else
      _ -> {:error, :destination_forbidden}
    end
  end

  defp resolve_destination(_), do: {:error, :destination_forbidden}

  # This is a configuration generation, never a credential. Jobs are cancelled
  # when the server changes repository identity, destinations, or revokes a secret.
  def generation(connection) do
    connection
    |> Map.drop([:destination])
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def same_generation?(key, generation) do
    case current(key) do
      {:ok, connection} -> generation(connection) == generation
      _ -> false
    end
  end
end
