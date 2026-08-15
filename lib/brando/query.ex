defmodule Brando.Query do
  @moduledoc """
  Public query API for Brando contexts.

  Contexts use the stable entry point:

      use Brando.Query

  The compiler and runtime engine are split internally to keep context
  compilation isolated. Callers should not depend on those implementation
  modules directly.

  ## Include

  `:include` provides a recursive, association-aware alternative to the lower-level
  `:preload` API. Association modules are inferred from the parent schema, and each
  include node can select fields, order its query, nest more includes, or start from
  a custom Ecto query.

      user_summary = [select: [:id, :username]]

      Comments.list_comments(%{
        select: {:struct, [:id, :parent_id, :user_id, :inserted_at]},
        include: [
          user: user_summary,
          children: [
            select: [:id, :parent_id, :user_id, :inserted_at],
            order: [desc: :inserted_at],
            include: [user: user_summary]
          ]
        ]
      })

  Partial selections must contain the parent-side association key needed to load
  each include. For example, a `:children` include needs the parent's `:id`, while
  a `:user` include needs its `:user_id`. Missing keys produce an `ArgumentError`
  when the query is built.

  `:preload` remains available unchanged for existing callers and as a low-level
  escape hatch. A custom query can also be supplied explicitly inside an include:

      include: [children: [query: comments_query, include: [:user]]]
  """

  alias Brando.Query.Compiler

  @runtime Module.concat(["Brando", "Query", "Runtime"])

  @doc "Imports Brando's query, mutation, reducer, and helper macros."
  defmacro __using__(_opts), do: Compiler.build_use()

  @doc "Defines list or single-entry query functions for a Blueprint schema."
  defmacro query(kind, module, do: block) when kind in [:list, :single] do
    Compiler.build_query(kind, module, block, __CALLER__)
  end

  @doc "Defines generated create, update, delete, or duplicate mutation functions."
  defmacro mutation(operation, module) when operation in [:create, :update, :delete, :duplicate] do
    Compiler.build_mutation(operation, module, nil, __CALLER__)
  end

  defmacro mutation(operation, module, do: callback)
           when operation in [:create, :update, :delete] do
    Compiler.build_mutation(operation, module, callback, __CALLER__)
  end

  @doc "Defines a context's list-query filter reducer."
  defmacro filters(module, do: block), do: Compiler.build_reducer(:filters, module, block, __CALLER__)

  @doc "Defines a context's single-query match reducer."
  defmacro matches(module, do: block), do: Compiler.build_reducer(:matches, module, block, __CALLER__)

  @doc "Builds an Ecto fragment matching any JSON object value case-insensitively."
  defmacro jsonb_contains_any_value_ilike(field, value), do: Compiler.build_jsonb_contains(field, value)

  @doc "Applies one or more ordering expressions to a query."
  def with_order(query, order), do: runtime(:with_order, [query, order])

  @doc "Parses a query order string into its tuple representation."
  def order_string_to_list(order), do: runtime(:order_string_to_list, [order])

  @doc "Applies a select expression to a query."
  def with_select(query, fields), do: runtime(:with_select, [query, fields])

  @doc "Applies a status filter to a query."
  def with_status(query, status), do: runtime(:with_status, [query, status])

  @doc "Applies a language filter to a query."
  def with_language(query, language), do: runtime(:with_language, [query, language])

  @doc "Excludes one or more languages from a query."
  def with_exclude_language(query, language), do: runtime(:with_exclude_language, [query, language])

  @doc "Applies preload specifications to a query."
  def with_preload(query, preloads), do: runtime(:with_preload, [query, preloads])

  @doc "Applies recursive, association-aware include specifications to a query."
  def with_include(query, includes), do: runtime(:with_include, [query, includes])

  @doc "Applies association joins to a query."
  def with_join(query, joins), do: runtime(:with_join, [query, joins])

  @doc "Returns the stable cache hash for a query key."
  def hash_query(query_key), do: runtime(:hash_query, [query_key])

  @doc "Looks up a query result in Brando's query cache."
  @spec try_cache(any(), any()) :: {:hit, any()} | {:miss, any(), any()} | :no_cache
  def try_cache(query_key, cache_opts), do: runtime(:try_cache, [query_key, cache_opts])

  @doc "Reduces list query arguments into an Ecto query."
  def run_list_query_reducer(context, args, initial_query, module) do
    runtime(:run_list_query_reducer, [context, args, initial_query, module])
  end

  @doc "Reduces single-entry query arguments into an Ecto query or revision result."
  def run_single_query_reducer(context, args, module) do
    runtime(:run_single_query_reducer, [context, args, module])
  end

  @doc "Builds pagination metadata when pagination is enabled."
  def maybe_build_pagination_meta(query, args), do: runtime(:maybe_build_pagination_meta, [query, args])

  @doc "Inserts a changeset and evicts affected query caches."
  def insert(changeset, opts \\ []), do: runtime(:insert, [changeset, opts])

  @doc "Updates a changeset and evicts affected query caches."
  def update(changeset, opts \\ []), do: runtime(:update, [changeset, opts])

  @doc "Deletes an entry and evicts affected query caches."
  def delete(entry), do: runtime(:delete, [entry])

  @doc "Loads an entry with the canonical Blueprint preloads."
  def get_entry(schema, id), do: runtime(:get_entry, [schema, id])

  @doc "Executes a generated list query."
  def handle_list_query(context, query_key, args, initial_query, module, stream \\ false) do
    runtime(:handle_list_query, [context, query_key, args, initial_query, module, stream])
  end

  @doc "Executes a generated single-entry query."
  def handle_single_query(context, query_key, args, module, block, schema_atom) do
    runtime(:handle_single_query, [context, query_key, args, module, block, schema_atom])
  end

  @doc "Escapes SQL LIKE wildcard characters in a string or list of strings."
  def sanitize_ilike_pattern(text), do: runtime(:sanitize_ilike_pattern, [text])

  defp runtime(function, arguments), do: apply(@runtime, function, arguments)
end
