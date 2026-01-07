defmodule Brando.Content.Identifier.Queries do
  @moduledoc """
  Query functions for identifiers.

  Provides functions for listing, fetching, and generating identifiers.
  """

  alias Brando.Content.Identifier

  @doc """
  Lists available entry types for the identifier picker.

  Returns all blueprints plus the Page schema as selectable entry types.

  ## Examples

      iex> list_entry_types()
      {:ok, [{"articles", MyApp.Blog.Article}, {"pages", Brando.Pages.Page}]}
  """
  @spec list_entry_types() :: {:ok, [{String.t(), module()}]}
  def list_entry_types do
    blueprints = Brando.Blueprint.list_blueprints() ++ [Brando.Pages.Page]
    entry_types = Enum.map(blueprints, &{Brando.Blueprint.get_plural(&1), &1})
    {:ok, entry_types}
  end

  @doc """
  Transforms wanted_types into entry type tuples with list options.

  ## Examples

      iex> get_entry_types([{MyApp.Blog.Article, %{limit: 10}}])
      [{"articles", MyApp.Blog.Article, %{limit: 10}}]
  """
  @spec get_entry_types([{module(), map()}]) :: [{String.t(), module(), map()}]
  def get_entry_types(wanted_types) do
    wanted_types
    |> Enum.reduce([], fn {wanted_type, list_opts}, acc ->
      [{Brando.Blueprint.get_plural(wanted_type), wanted_type, list_opts} | acc]
    end)
    |> Enum.reverse()
  end

  @doc """
  Lists identifiers for a given schema.

  Accepts either a module atom or a string representation of the module.

  ## Examples

      iex> list_entries_for(MyApp.Blog.Article)
      {:ok, [%Identifier{}, ...]}

      iex> list_entries_for("MyApp.Blog.Article", %{language: "en"})
      {:ok, [%Identifier{}, ...]}
  """
  @spec list_entries_for(module() | String.t(), map()) :: {:ok, [Identifier.t()]}
  def list_entries_for(schema, list_opts \\ %{})

  def list_entries_for(schema_binary, list_opts) when is_binary(schema_binary) do
    schema_binary
    |> List.wrap()
    |> Module.concat()
    |> list_entries_for(list_opts)
  end

  def list_entries_for(schema, list_opts) when is_atom(schema) do
    Brando.Content.list_identifiers(schema, list_opts)
  end

  @doc """
  Retrieves the full entry for an identifier.

  Loads the entry from the database with all preloads required by the schema.

  ## Examples

      iex> get_entry_for_identifier(%Identifier{entry_id: 1, schema: MyApp.Blog.Article})
      {:ok, %MyApp.Blog.Article{...}}

      iex> get_entry_for_identifier(%Identifier{schema: NonExistent})
      {:error, :module_does_not_exist}
  """
  @spec get_entry_for_identifier(Identifier.t()) :: {:ok, map()} | {:error, atom()}
  def get_entry_for_identifier(%Identifier{entry_id: entry_id, schema: schema}) do
    if function_exported?(schema, :__info__, 1) do
      context = schema.__modules__().context
      singular = schema.__naming__().singular
      preloads = Brando.Blueprint.preloads_for(schema)
      opts = %{matches: %{id: entry_id}, preload: preloads}
      apply(context, :"get_#{singular}", [opts])
    else
      {:error, :module_does_not_exist}
    end
  end

  @doc """
  Generates identifiers for a list of entries.

  ## Examples

      iex> identifiers_for([%Article{}, %Article{}])
      {:ok, [%Identifier{}, %Identifier{}]}
  """
  @spec identifiers_for([map()]) :: {:ok, [Identifier.t() | nil]}
  def identifiers_for(entries) do
    {:ok, Enum.map(entries, &identifier_for/1)}
  end

  @doc """
  Generates identifiers for a list of entries (unwrapped).

  ## Examples

      iex> identifiers_for!([%Article{}, %Article{}])
      [%Identifier{}, %Identifier{}]
  """
  @spec identifiers_for!([map()]) :: [Identifier.t() | nil]
  def identifiers_for!(entries) do
    Enum.map(entries, &identifier_for/1)
  end

  @doc """
  Generates an identifier for a single entry.

  Returns `nil` if the schema doesn't support identifiers.

  ## Examples

      iex> identifier_for(%Article{id: 1, title: "Hello"})
      %Identifier{entry_id: 1, title: "Hello", ...}

      iex> identifier_for(%SchemaWithoutIdentifier{})
      nil
  """
  @spec identifier_for(map()) :: Identifier.t() | nil
  def identifier_for(%{__struct__: schema} = entry) do
    if function_exported?(schema, :__identifier__, 1) do
      schema.__identifier__(entry)
    else
      nil
    end
  end
end
