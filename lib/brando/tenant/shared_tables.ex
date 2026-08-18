defmodule Brando.Tenant.SharedTables do
  @moduledoc """
  The tables that always live in `public`, never inside a tenant schema.

  Registry, authentication, session, job, and migration-history tables are
  shared across every site and environment. Structure cloning skips them when
  provisioning an environment, data migration refuses to copy them, and foreign
  keys that point at them keep their `public` qualifier.

  Because everything else in `public` is treated as tenant content, an
  application with its own cross-site tables must declare them:

      config :brando, :shared_tables, ["billing_accounts", "feature_flags"]

  Without that, such a table would be cloned into every environment schema and
  its rows copied along with the content.
  """

  @shared ~w(
    environments
    environment_operation_logs
    schema_migrations
    site_asset_sets
    ssg_builds
    sites
    sites_previews
    uploads_pending_intents
    user_sites
    user_tokens
    users
    users_tokens
  )

  @oban_prefix "oban_"

  @doc "Returns Brando's own shared table names, without application additions."
  @spec list() :: [String.t()]
  def list, do: @shared

  @doc "Returns every shared table name, including application additions."
  @spec all() :: [String.t()]
  def all, do: @shared ++ configured()

  @doc """
  Returns true when a table is pinned to `public`.

  Every `oban_*` table is shared. Oban is configured against `public`, and Oban
  Pro adds tables beyond `oban_jobs`, so the prefix is matched rather than each
  table being enumerated.
  """
  @spec member?(String.t()) :: boolean()
  def member?(table) when is_binary(table) do
    table in @shared or String.starts_with?(table, @oban_prefix) or table in configured()
  end

  defp configured do
    :shared_tables |> Brando.config() |> List.wrap() |> Enum.map(&to_string/1)
  end

  @doc "Splits table names into `{tenant_tables, shared_tables}`."
  @spec split([String.t()]) :: {[String.t()], [String.t()]}
  def split(tables), do: Enum.split_with(tables, &(not member?(&1)))
end
