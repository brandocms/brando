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
  @callback __identifier__(entry :: map) :: map

  @doc "Returns an absolute URL to your entry (or false if it does not have one)"
  @callback __absolute_url__(entry :: map) :: binary | false

  defmacro __using__(_) do
    quote do
      @behaviour Brando.Schema
      import Brando.Schema, only: [identifier: 1, absolute_url: 1]
    end
  end

  @doc """
  Set the field that will be used to identify the entry
  """
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
          cover: cover
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

        unquote(fun).(routes, endpoint, entry)
      end
    end
  end

  def identifiers_for(entries) do
    Enum.map(entries, &identifier_for/1)
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
end
