defmodule Brando.RuntimeConfig do
  @moduledoc """
  Lightweight access to Brando application configuration and module names.

  This module deliberately has no dependencies on the Brando application or
  supervisor, so low-level rendering and schema infrastructure can read
  configuration without creating a dependency back to application startup.
  """

  @images_config_key :"Elixir.Brando.Images"

  @doc """
  Gets the configuration for `key` under the `:brando` application.
  """
  @spec get(term()) :: term()
  def get(key), do: Application.get_env(:brando, key)

  @doc """
  Gets `key` from a module's keyword configuration.
  """
  @spec get(module(), term()) :: term()
  def get(module, key), do: Keyword.get(Application.get_env(:brando, module), key, nil)

  @doc """
  Gets `key` from the `Brando.Images` application configuration without adding
  a code dependency on the database-backed Images context.
  """
  @spec images(term()) :: term()
  def images(key), do: Keyword.get(Application.get_env(:brando, @images_config_key), key, nil)

  @doc """
  Resolves a module under the configured parent application module.
  """
  @spec app_module(module()) :: module()
  def app_module(module), do: Module.concat(get(:app_module), module)

  @doc """
  Resolves a module under the configured admin module.
  """
  @spec admin_module(module()) :: module()
  def admin_module(module), do: Module.concat(get(:admin_module), module)

  @doc """
  Resolves a module under the configured web module.
  """
  @spec web_module(module()) :: module()
  def web_module(module), do: Module.concat(get(:web_module), module)

  @doc """
  Resolves the configured Phoenix endpoint module.
  """
  @spec endpoint() :: module()
  def endpoint, do: get(:endpoint_module) || web_module(Endpoint)

  @doc "Resolves the configured Phoenix router module."
  @spec router() :: module()
  def router, do: get(:router_module) || web_module(Router)

  @doc """
  Resolves the configured Phoenix router helpers module.
  """
  @spec router_helpers() :: module()
  def router_helpers, do: Module.concat(router(), Helpers)

  @doc """
  Resolves the configured Gettext module.
  """
  @spec gettext() :: module()
  def gettext, do: web_module(Gettext)
end
