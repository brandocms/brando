defmodule Brando.Tenant do
  @moduledoc """
  Tenant configuration and process-local schema-prefix context.

  Tenancy is disabled by default. In that mode `current_prefix/0` always
  returns `nil`, preserving Brando's existing public-schema behavior. The
  environment phase is responsible for setting a prefix at request and
  LiveView boundaries when tenancy is enabled.
  """

  alias Brando.Environments.Environment
  alias Brando.Exception.ConfigError
  alias Brando.Sites.Site

  @type mode :: :none | :single | :multi

  @modes [:none, :single, :multi]
  @key_format ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/
  @prefix_format ~r/^tenant_[a-z0-9]+(?:-[a-z0-9]+)*_[a-z0-9]+(?:-[a-z0-9]+)*$/
  @process_prefix_key {__MODULE__, :current_prefix}

  @spec mode() :: mode()
  def mode do
    case Brando.config(:tenancy_mode) || :none do
      mode when mode in @modes -> mode
      invalid -> raise_invalid_mode(invalid)
    end
  end

  @spec enabled?() :: boolean()
  def enabled?, do: mode() != :none

  @spec prefix(Site.t(), Environment.t()) :: String.t()
  def prefix(%Site{key: site_key}, %Environment{key: environment_key}) do
    prefix(site_key, environment_key)
  end

  @spec prefix(String.t(), String.t()) :: String.t()
  def prefix(site_key, environment_key) do
    unless valid_key?(site_key) and valid_key?(environment_key) do
      raise ArgumentError, "site and environment keys must be lowercase, URL-safe keys"
    end

    "tenant_#{site_key}_#{environment_key}"
  end

  @spec current_prefix() :: String.t() | nil
  def current_prefix do
    if enabled?(), do: Process.get(@process_prefix_key), else: nil
  end

  @spec put_prefix(String.t() | nil) :: String.t() | nil
  def put_prefix(nil) do
    Process.delete(@process_prefix_key)
  end

  def put_prefix(prefix) when is_binary(prefix) do
    if Regex.match?(@prefix_format, prefix) do
      Process.put(@process_prefix_key, prefix)
    else
      raise ArgumentError, "invalid tenant prefix: #{inspect(prefix)}"
    end
  end

  @spec with_prefix(String.t(), (-> result)) :: result when result: var
  def with_prefix(prefix, fun) when is_function(fun, 0) do
    previous = Process.get(@process_prefix_key)
    put_prefix(prefix)

    try do
      fun.()
    after
      put_prefix(previous)
    end
  end

  @spec validate_config!() :: :ok
  def validate_config! do
    case mode() do
      :single -> validate_single_site_key!()
      _ -> :ok
    end
  end

  @spec valid_key?(term()) :: boolean()
  def valid_key?(key), do: is_binary(key) and Regex.match?(@key_format, key)

  defp validate_single_site_key! do
    case Brando.config(:site_key) do
      site_key when is_binary(site_key) ->
        if valid_key?(site_key), do: :ok, else: raise_invalid_site_key(site_key)

      site_key ->
        raise_invalid_site_key(site_key)
    end
  end

  defp raise_invalid_mode(mode) do
    raise ConfigError,
      message: "Invalid :tenancy_mode configuration: #{inspect(mode)}. Expected one of #{inspect(@modes)}."
  end

  defp raise_invalid_site_key(site_key) do
    raise ConfigError,
      message: """
      Invalid or missing :site_key configuration for tenancy_mode: :single.

      Expected a lowercase, URL-safe key, for example:

          config :brando, tenancy_mode: :single, site_key: "my-site"

      Got: #{inspect(site_key)}
      """
  end
end
