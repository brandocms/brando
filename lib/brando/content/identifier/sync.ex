defmodule Brando.Content.Identifier.Sync do
  @moduledoc """
  Synchronization and maintenance operations for identifiers.

  Provides functions to clean up invalid identifiers, update existing ones,
  and create missing identifiers for entries.
  """

  import Ecto.Query

  alias Brando.Content.Identifier
  alias Brando.Content.Identifier.Queries
  alias Brando.Content.Identifier.Registry

  @doc """
  Cleans up invalid identifiers and updates existing ones.

  This operation:
  1. Removes identifiers for schemas no longer in the application
  2. Removes identifiers for deleted or non-existent entries
  3. Updates existing identifier data to match current entry state
  4. Creates identifiers for entries missing them

  Typically called via `mix brando.identifiers.sync`.
  """
  @spec sync() :: :ok
  def sync do
    relevant_modules = Registry.list_persistent_identifier_modules(:include_brando)

    IO.puts("=> Syncing identifiers. Relevant modules: #{inspect(relevant_modules)}")

    # Remove identifiers for schemas no longer in application
    delete_query = from(i in Identifier, where: i.schema not in ^relevant_modules)
    Brando.Repo.delete_all(delete_query, [])

    log_red("[-] Removing irrelevant identifiers")

    # Process each existing identifier
    {:ok, identifiers} = Brando.Content.list_identifiers()

    for identifier <- identifiers do
      process_identifier(identifier)
    end

    # Create any missing identifiers
    create_missing_identifiers()

    :ok
  end

  @doc """
  Creates identifiers for entries that don't have one yet.

  Iterates through all modules with persistent identifiers and creates
  identifiers for any entries that are missing them.
  """
  @spec create_missing_identifiers() :: :ok
  def create_missing_identifiers do
    relevant_modules = Registry.list_persistent_identifier_modules(:include_brando)

    for module <- relevant_modules do
      create_missing_identifiers_for_module(module)
    end

    :ok
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

    for entry <- entries do
      {:ok, identifier} = Brando.Content.create_identifier(module, entry)

      if identifier do
        log_green(
          "[+] Creating identifier ##{inspect(identifier.id)} in schema #{inspect(identifier.schema)} for entry_id ##{identifier.entry_id}"
        )
      end
    end
  end

  defp process_identifier(identifier) do
    case Queries.get_entry_for_identifier(identifier) do
      {:error, :module_does_not_exist} ->
        log_red("[-] Could not find schema #{inspect(identifier.schema)} in application. Deleting identifier")

        Brando.Content.delete_identifier(identifier)

      {:error, _} ->
        log_red(
          "[-] Could not find entry for identifier #{inspect(identifier.id)} in schema #{inspect(identifier.schema)}. Deleting identifier"
        )

        Brando.Content.delete_identifier(identifier)

      {:ok, %{deleted_at: deleted_at}} when not is_nil(deleted_at) ->
        log_red(
          "[-] Entry for identifier #{inspect(identifier.id)} in schema #{inspect(identifier.schema)} is marked as deleted. Deleting identifier"
        )

        Brando.Content.delete_identifier(identifier)

      {:ok, entry} ->
        log_green(
          "[+] Updating identifier for identifier #{inspect(identifier.id)} in schema #{inspect(identifier.schema)}"
        )

        Brando.Content.update_identifier(entry.__struct__, entry)
    end
  end

  defp log_red(message) do
    IO.puts(IO.ANSI.red() <> message <> IO.ANSI.reset())
  end

  defp log_green(message) do
    IO.puts(IO.ANSI.green() <> message <> IO.ANSI.reset())
  end
end
