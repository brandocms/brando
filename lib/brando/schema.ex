defmodule Brando.Schema do
  @moduledoc """
  Brando schemas need some help in identifying entries.

  If your entry does not have an absolute URL, you can return false

  ## Example

      ```
      use Brando.Schema

      # This will use the entry's title field to identify the entry
      identifier fn entry -> entry.title end

      absolute_url fn router, endpoint, entry ->
        router.page_path(endpoint, :detail, entry.slug)
      end
      ```
  """

  @doc "Identifies your entry"
  @callback __identifier__(entry :: map) :: map | nil

  @doc "Returns an absolute URL to your entry (or false if it does not have one)"
  @callback __absolute_url__(entry :: map) :: binary | false

  @doc "Returns a meta map for schema"
  @callback __meta__(locale :: atom, key :: atom) :: binary

  defmacro __using__(_) do
    quote do
      @behaviour Brando.Schema
      import Brando.Schema, only: [identifier: 1, absolute_url: 1, meta: 2]
    end
  end

  defmacro meta(language, opts) do
    language = (is_binary(language) && String.to_existing_atom(language)) || language
    singular = Keyword.fetch!(opts, :singular)
    plural = Keyword.fetch!(opts, :plural)

    quote do
      @impl Brando.Schema
      def __meta__(unquote(language), :singular), do: unquote(singular)
      def __meta__(unquote(language), :plural), do: unquote(plural)
    end
  end

  @doc """
  Set the field that will be used to identify the entry
  """
  defmacro identifier(false) do
    quote do
      @impl Brando.Schema
      def __identifier__(entry) do
        nil
      end
    end
  end

  defmacro identifier(fun) do
    quote do
      @impl Brando.Schema
      def __identifier__(entry) do
        title = unquote(fun).(entry)

        type =
          __MODULE__
          |> Module.split()
          |> List.last()

        translated_type = Gettext.dgettext(Brando.gettext(), "default", type)
        status = Map.get(entry, :status, nil)
        absolute_url = __MODULE__.__absolute_url__(entry)
        cover = Brando.Schema.extract_cover(entry)

        %{
          id: entry.id,
          title: title,
          type: translated_type,
          status: status,
          absolute_url: absolute_url,
          cover: cover,
          schema: __MODULE__
        }
      end
    end
  end

  defmacro absolute_url(false) do
    quote do
      @impl Brando.Schema
      def __absolute_url__(_) do
        false
      end
    end
  end

  defmacro absolute_url(fun) do
    quote do
      @impl Brando.Schema
      def __absolute_url__(entry) do
        routes = Brando.helpers()
        endpoint = Brando.endpoint()

        try do
          unquote(fun).(routes, endpoint, entry)
        rescue
          _ -> nil
        end
      end
    end
  end

  @spec identifiers_for([map]) :: {:ok, list}
  def identifiers_for(entries) do
    {:ok, Enum.map(entries, &identifier_for/1)}
  end

  def identifier_for(%{__struct__: schema} = entry) do
    schema.__identifier__(entry)
  end

  def extract_cover(%{cover: nil}) do
    nil
  end

  def extract_cover(%{cover: cover}) do
    Brando.Utils.img_url(cover, :thumb, prefix: Brando.Utils.media_url())
  end

  def extract_cover(_) do
    nil
  end

  @doc """
  List all schemas
  """
  @spec list_schemas :: [module()]
  def list_schemas do
    {:ok, app_modules} = :application.get_key(Brando.otp_app(), :modules)

    app_modules
    |> Enum.uniq()
    |> Enum.filter(&is_schema/1)
  end

  def is_schema(module) do
    {:__schema__, 1} in module.__info__(:functions)
  end

  def list_entry_types(locale) do
    schemas = list_schemas() ++ [Brando.Pages.Page]
    entry_types = Enum.map(schemas, &{get_translated_plural(&1, locale), &1})
    {:ok, entry_types}
  end

  def get_context_for(schema_module) do
    schema_module
    |> Module.split()
    |> Enum.drop(-1)
    |> Module.concat()
  end

  @doc """
  Get singular for `schema_module`
  """
  def get_singular_for(schema_module) do
    schema_module
    |> Module.split()
    |> List.last()
    |> Inflex.underscore()
  end

  def list_entries_for(schema) do
    list_opts = %{}
    context = get_context_for(schema)

    singular =
      schema
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()

    plural = Inflex.pluralize(singular)
    {:ok, entries} = apply(context, :"list_#{plural}", [list_opts])
    identifiers_for(entries)
  end

  def metaless_schemas do
    Enum.reduce(list_schemas(), [], fn schema, acc ->
      acc =
        if {:__identifier__, 1} in schema.__info__(:functions) do
          acc
        else
          IO.warn("""
          Schema `#{inspect(schema)}` is missing `identifier`.

              use Brando.Schema

              identifier entry -> entry.title end

          """)

          [schema | acc]
        end

      acc =
        if {:__meta__, 2} in schema.__info__(:functions) do
          acc
        else
          IO.warn("""
          Schema `#{inspect(schema)}` is missing `meta`.

              use Brando.Schema

              meta :en, singular: "post", plural: "posts"
              meta :no, singular: "post", plural: "poster"

          """)

          [schema | acc]
        end

      if {:__absolute_url__, 1} in schema.__info__(:functions) do
        acc
      else
        IO.warn("""
        Schema `#{inspect(schema)}` is missing `absolute_url`.
        If your entries have URLs:

            use Brando.Schema

            absolute_url fn router, endpoint, entry ->
              router.post_path(endpoint, :detail, entry.slug)
            end

        If they don't

            use Brando.Schema

            absolute_url false

        """)

        [schema | acc]
      end
    end)
    |> Enum.uniq()
  end

  defp get_translated_plural(module, locale) do
    locale_atom = String.to_existing_atom(locale)
    module.__meta__(locale_atom, :plural)
  end
end
