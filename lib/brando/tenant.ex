defmodule Brando.Tenant do
  @moduledoc """
  Tenant configuration and process-local schema-prefix context.

  Tenancy is disabled by default. In that mode `current_prefix/0` always
  returns `nil`, preserving Brando's existing public-schema behavior. The
  environment phase is responsible for setting a prefix at request and
  LiveView boundaries when tenancy is enabled.
  """

  alias Brando.Authorization.Boundary
  alias Brando.Environments.Environment
  alias Brando.Exception.ConfigError
  alias Brando.Sites.Site

  @type mode :: :none | :single | :multi

  @modes [:none, :single, :multi]
  @key_format ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/
  @prefix_format ~r/^tenant_[a-z0-9]+(?:-[a-z0-9]+)*_[a-z0-9]+(?:-[a-z0-9]+)*$/
  @process_prefix_key {__MODULE__, :current_prefix}
  @process_public_key {__MODULE__, :public}

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

  @doc "Returns the site key encoded in the current tenant prefix."
  @spec current_site_key() :: String.t() | nil
  def current_site_key do
    case current_prefix() do
      "tenant_" <> remainder ->
        case String.split(remainder, "_", parts: 2) do
          [site_key, _environment_key] -> site_key
          _invalid -> nil
        end

      _no_prefix ->
        nil
    end
  end

  @doc "Namespaces an application cache key by the active tenant prefix."
  @spec cache_key(term(), String.t() | nil) :: term()
  def cache_key(key, prefix \\ current_prefix()) do
    if is_binary(prefix), do: {:tenant, prefix, key}, else: key
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

  @doc """
  Runs `fun` with no tenant prefix, reading and writing `public`'s copy of
  site tables on purpose, as the shared library does. In multi-site mode
  `Brando.Repo` refuses a query on a site table with no prefix anywhere else
  (`Brando.Exception.MissingTenantError`).
  """
  @spec with_public((-> result)) :: result when result: var
  def with_public(fun) when is_function(fun, 0) do
    previous = {Process.get(@process_prefix_key), Process.get(@process_public_key)}
    put_public()

    try do
      fun.()
    after
      {prefix, public} = previous
      put_prefix(prefix)
      if public, do: Process.put(@process_public_key, true), else: Process.delete(@process_public_key)
    end
  end

  @doc """
  Clears the tenant prefix for the rest of the process and marks its queries
  on site tables as meant for `public` (see `with_public/1`). For a LiveView
  that works on the shared library.
  """
  @spec put_public() :: :ok
  def put_public do
    put_prefix(nil)
    Process.put(@process_public_key, true)
    :ok
  end

  @doc """
  Whether the process is outside every site in multi-site mode: no tenant
  prefix, and not working on `public` on purpose (`with_public/1`). Account
  emails and the installation's own screens run so; a site's identity, SEO,
  globals and menus are then empty.
  """
  @spec outside_site?() :: boolean()
  def outside_site?, do: mode() == :multi and is_nil(current_prefix()) and not public?()

  @doc "Whether the process works on `public`'s copy of site tables on purpose (`with_public/1`)."
  @spec public?() :: boolean()
  def public?, do: Process.get(@process_public_key, false) and is_nil(Process.get(@process_prefix_key))

  @doc """
  Captures the current tenant context for work that will run in another process.
  The authorization scope comes along (`Brando.Authorization.Boundary.capture/0`),
  so queries there are narrowed as the caller's are, and so does the trace
  context, so spans there join the caller's trace.
  """
  @spec capture_context((-> result)) :: (-> result) when result: var
  def capture_context(fun) when is_function(fun, 0) do
    context = capture()
    fn -> run_in(context, fun) end
  end

  @spec capture_context((arg -> result)) :: (arg -> result) when arg: var, result: var
  def capture_context(fun) when is_function(fun, 1) do
    context = capture()
    fn arg -> run_in(context, fn -> fun.(arg) end) end
  end

  defp capture, do: {captured_prefix(), Brando.Tracing.capture(), Boundary.capture()}

  defp run_in({prefix, trace, authorization}, fun),
    do: Boundary.with_captured(authorization, fn -> run_captured(prefix, trace, fun) end)

  defp captured_prefix, do: if(public?(), do: :public, else: current_prefix())

  @spec validate_config!() :: :ok
  def validate_config! do
    case mode() do
      :single -> validate_single_site_key!()
      _ -> :ok
    end
  end

  @spec valid_key?(term()) :: boolean()
  def valid_key?(key), do: is_binary(key) and Regex.match?(@key_format, key)

  @spec valid_prefix?(term()) :: boolean()
  def valid_prefix?(prefix), do: is_binary(prefix) and Regex.match?(@prefix_format, prefix)

  defp validate_single_site_key! do
    case Brando.config(:site_key) do
      site_key when is_binary(site_key) ->
        if valid_key?(site_key), do: :ok, else: raise_invalid_site_key(site_key)

      site_key ->
        raise_invalid_site_key(site_key)
    end
  end

  defp run_captured(nil, trace, fun), do: Brando.Tracing.with_context(trace, fun)
  defp run_captured(:public, trace, fun), do: Brando.Tracing.with_context(trace, fn -> with_public(fun) end)
  defp run_captured(prefix, trace, fun), do: Brando.Tracing.with_context(trace, fn -> with_prefix(prefix, fun) end)

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
