defmodule Brando.Blueprint.Listings do
  @moduledoc """
  ### Listings
  """

  defmodule Listing do
    defstruct label: nil,
              query: %{},
              fields: []
  end

  defmodule Field do
    defstruct name: nil,
              type: nil,
              opts: []
  end

  defmodule Template do
    defstruct template: nil,
              opts: []
  end

  defmacro listings(do: block) do
    listings(__CALLER__, block)
  end

  defp listings(_caller, block) do
    quote generated: true, location: :keep do
      Module.register_attribute(__MODULE__, :listings, accumulate: true)
      unquote(block)
    end
  end

  defmacro listing(label, do: block) do
    do_listing(label, block)
  end

  defmacro listing(do: block) do
    do_listing(nil, block)
  end

  defp do_listing(label, block) do
    quote location: :keep do
      var!(brando_listing_fields) = []
      var!(brando_listing_query) = %{}
      unquote(block)

      named_listing =
        build_listing(
          unquote(label),
          var!(brando_listing_query),
          Enum.reverse(var!(brando_listing_fields))
        )

      Module.put_attribute(__MODULE__, :listings, named_listing)
    end
  end

  defmacro listing_field(name, type, opts \\ []) do
    quote location: :keep,
          bind_quoted: [name: name, type: type, opts: opts] do
      var!(brando_listing_fields) =
        List.wrap(build_field(name, type, opts)) ++ var!(brando_listing_fields)
    end
  end

  defmacro listing_template(template, opts \\ []) do
    quote location: :keep,
          bind_quoted: [template: template, opts: opts] do
      var!(brando_listing_fields) =
        List.wrap(build_template(template, opts)) ++ var!(brando_listing_fields)
    end
  end

  defmacro listing_query(query) do
    quote location: :keep,
          bind_quoted: [query: query] do
      var!(brando_listing_query) = query
    end
  end

  def build_listing(label, query, fields) do
    %__MODULE__.Listing{
      label: label,
      query: query,
      fields: fields
    }
  end

  def build_template(template, opts) do
    %__MODULE__.Template{
      template: template,
      opts: opts
    }
  end

  def build_field(name, type, opts) do
    %__MODULE__.Field{
      name: name,
      type: type,
      opts: opts
    }
  end
end
