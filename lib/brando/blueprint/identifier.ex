defmodule Brando.Blueprint.Identifier do
  @moduledoc """
  Identifier DSL and utilities for blueprints.

  This module provides backward-compatible access to identifier functionality.
  The actual implementation is split into focused submodules:

  - `Brando.Blueprint.Identifier.DSL` - DSL macros for blueprints
  - `Brando.Blueprint.Identifier.Generator` - Runtime identifier generation
  - `Brando.Blueprint.Identifier.Template` - Template parsing
  - `Brando.Content.Identifier.Queries` - Query functions
  - `Brando.Content.Identifier.Sync` - Sync operations
  - `Brando.Content.Identifier.Registry` - Module registry

  ## Usage in blueprints

  The identifier DSL is automatically available when using `Brando.Blueprint`:

      use Brando.Blueprint,
        application: "MyApp",
        domain: "Blog",
        ...

      identifier "{{ entry.title }}"

  ## Querying

      Brando.Content.Identifier.Queries.list_entries_for(MySchema)
  """

  # Backward compatibility delegations for runtime functions

  @doc """
  Generates an identifier struct from an entry.

  Delegated to `Brando.Blueprint.Identifier.Generator.generate/4`.
  """
  defdelegate handle_identifier(module, entry, parsed_identifier, opts),
    to: Brando.Blueprint.Identifier.Generator,
    as: :generate

  @doc """
  Extracts cover image URL from an entry.

  Delegated to `Brando.Blueprint.Identifier.Generator.extract_cover/2`.
  """
  defdelegate extract_cover(field, entry), to: Brando.Blueprint.Identifier.Generator

  @doc """
  Extracts field references from identifier template.

  Delegated to `Brando.Blueprint.Identifier.Template.extract_fields/1`.
  """
  defdelegate extract_fields_from_identifier(template),
    to: Brando.Blueprint.Identifier.Template,
    as: :extract_fields

  # Query function delegations

  @doc """
  Lists available entry types.

  Delegated to `Brando.Content.Identifier.Queries.list_entry_types/0`.
  """
  defdelegate list_entry_types(), to: Brando.Content.Identifier.Queries

  @doc """
  Transforms wanted types into entry type tuples.

  Delegated to `Brando.Content.Identifier.Queries.get_entry_types/1`.
  """
  defdelegate get_entry_types(wanted_types), to: Brando.Content.Identifier.Queries

  @doc """
  Lists identifiers for a schema.

  Delegated to `Brando.Content.Identifier.Queries.list_entries_for/2`.
  """
  defdelegate list_entries_for(schema, list_opts \\ %{}), to: Brando.Content.Identifier.Queries

  @doc """
  Gets the full entry for an identifier.

  Delegated to `Brando.Content.Identifier.Queries.get_entry_for_identifier/1`.
  """
  defdelegate get_entry_for_identifier(identifier), to: Brando.Content.Identifier.Queries

  @doc """
  Generates identifiers for entries (wrapped).

  Delegated to `Brando.Content.Identifier.Queries.identifiers_for/1`.
  """
  defdelegate identifiers_for(entries), to: Brando.Content.Identifier.Queries

  @doc """
  Generates identifiers for entries (unwrapped).

  Delegated to `Brando.Content.Identifier.Queries.identifiers_for!/1`.
  """
  defdelegate identifiers_for!(entries), to: Brando.Content.Identifier.Queries

  @doc """
  Generates identifier for a single entry.

  Delegated to `Brando.Content.Identifier.Queries.identifier_for/1`.
  """
  defdelegate identifier_for(entry), to: Brando.Content.Identifier.Queries

  # Sync function delegations

  @doc """
  Synchronizes all identifiers.

  Delegated to `Brando.Content.Identifier.Sync.sync/0`.
  """
  defdelegate sync(), to: Brando.Content.Identifier.Sync

  @doc """
  Creates missing identifiers.

  Delegated to `Brando.Content.Identifier.Sync.create_missing_identifiers/0`.
  """
  defdelegate create_missing_identifiers(), to: Brando.Content.Identifier.Sync
end
