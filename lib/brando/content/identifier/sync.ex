defmodule Brando.Content.Identifier.Sync do
  @moduledoc """
  Synchronization and maintenance operations for identifiers.

  Provides functions to clean up invalid identifiers, update existing ones,
  and create missing identifiers for entries.
  """

  import Ecto.Query

  alias Brando.Content
  alias Brando.Content.Identifier
  alias Brando.Content.Identifier.Queries
  alias Brando.Content.Identifier.Registry

  @typedoc "What failed (entry or schema) and the exception it raised"
  @type failure :: {String.t(), Exception.t()}

  @doc """
  Cleans up invalid identifiers and updates existing ones.

  This operation:
  1. Removes identifiers for schemas no longer in the application
  2. Removes identifiers for deleted or non-existent entries
  3. Updates existing identifier data to match current entry state
  4. Creates identifiers for entries missing them

  An entry that raises (for example an `absolute_url` that reads a missing
  association) is logged and skipped, and the sync carries on. The failures
  are listed at the end and returned as `{:error, failures}`.

  `modules:` replaces the registry's list of schemas with identifiers, mostly
  for tests. Identifiers for any other schema are removed, as they would be
  for a schema the application no longer has.

  Typically called via `mix brando.identifiers.sync`.
  """
  @spec sync(keyword()) :: :ok | {:error, [failure()]}
  def sync(opts \\ []) do
    relevant_modules = relevant_modules(opts)

    IO.puts("=> Syncing identifiers. Relevant modules: #{inspect(relevant_modules)}")

    # Remove identifiers for schemas no longer in application
    delete_query = from(i in Identifier, where: i.schema not in ^relevant_modules)
    Brando.Repo.delete_all(delete_query, [])

    log_red("[-] Removing irrelevant identifiers")

    # Process each existing identifier
    {:ok, identifiers} = Content.list_identifiers()

    update_failures =
      Enum.flat_map(identifiers, fn identifier ->
        attempt("identifier ##{identifier.id} (#{inspect(identifier.schema)} ##{identifier.entry_id})", fn ->
          process_identifier(identifier)
        end)
      end)

    # Create any missing identifiers
    create_failures =
      case create_missing_identifiers(modules: relevant_modules) do
        :ok -> []
        {:error, failures} -> failures
      end

    report(update_failures ++ create_failures)
  end

  @doc """
  Creates identifiers for entries that don't have one yet.

  Iterates through all modules with persistent identifiers and creates
  identifiers for any entries that are missing them. Entries that raise are
  skipped and returned as `{:error, failures}`.
  """
  @spec create_missing_identifiers(keyword()) :: :ok | {:error, [failure()]}
  def create_missing_identifiers(opts \\ []) do
    opts
    |> relevant_modules()
    |> Enum.flat_map(fn module ->
      attempt(inspect(module), fn -> create_missing_identifiers_for_module(module) end)
    end)
    |> case do
      [] -> :ok
      failures -> {:error, failures}
    end
  end

  defp relevant_modules(opts) do
    Keyword.get_lazy(opts, :modules, fn ->
      Registry.list_persistent_identifier_modules(:include_brando)
    end)
  end

  defp create_missing_identifiers_for_module(module) do
    # Get entry IDs that already have identifiers
    identifiers_query =
      from(i in Identifier, select: i.entry_id, where: i.schema == ^module)

    current_identifiers = Brando.Repo.all(identifiers_query)

    # Get entries without identifiers
    preloads = Brando.Blueprint.preloads_for(module)

    entries_query =
      from(e in module, where: e.id not in ^current_identifiers, preload: ^preloads)

    entries = Brando.Repo.all(entries_query)

    Enum.flat_map(entries, fn entry ->
      attempt("#{inspect(module)} ##{entry.id}", fn -> create_identifier(module, entry) end)
    end)
  end

  defp create_identifier(module, entry) do
    {:ok, identifier} = Content.create_identifier(module, entry)

    if identifier do
      log_green(
        "[+] Creating identifier ##{inspect(identifier.id)} in schema #{inspect(identifier.schema)} for entry_id ##{identifier.entry_id}"
      )
    end

    []
  end

  defp process_identifier(identifier) do
    case Queries.get_entry_for_identifier(identifier) do
      {:error, :module_does_not_exist} ->
        log_red("[-] Could not find schema #{inspect(identifier.schema)} in application. Deleting identifier")

        Content.delete_identifier(identifier)

      {:error, _} ->
        log_red(
          "[-] Could not find entry for identifier #{inspect(identifier.id)} in schema #{inspect(identifier.schema)}. Deleting identifier"
        )

        Content.delete_identifier(identifier)

      {:ok, %{deleted_at: deleted_at}} when not is_nil(deleted_at) ->
        log_red(
          "[-] Entry for identifier #{inspect(identifier.id)} in schema #{inspect(identifier.schema)} is marked as deleted. Deleting identifier"
        )

        Content.delete_identifier(identifier)

      {:ok, entry} ->
        log_green(
          "[+] Updating identifier for identifier #{inspect(identifier.id)} in schema #{inspect(identifier.schema)}"
        )

        Content.update_identifier(entry.__struct__, entry)
    end

    []
  end

  # Runs `fun`, which returns a list of nested failures. A raise becomes a
  # failure for `subject` instead of stopping the sync.
  defp attempt(subject, fun) do
    fun.()
  rescue
    exception ->
      log_red("[!] Skipping #{subject}: #{Exception.message(exception)}")
      [{subject, exception}]
  end

  defp report([]), do: :ok

  defp report(failures) do
    log_red("\n[!] #{length(failures)} identifier(s) could not be synced:")

    Enum.each(failures, fn {subject, exception} ->
      log_red("    #{subject}: #{Exception.message(exception)}")
    end)

    {:error, failures}
  end

  defp log_red(message) do
    IO.puts(IO.ANSI.red() <> message <> IO.ANSI.reset())
  end

  defp log_green(message) do
    IO.puts(IO.ANSI.green() <> message <> IO.ANSI.reset())
  end
end
