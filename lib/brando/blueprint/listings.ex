defmodule Brando.Blueprint.Listings do
  @moduledoc """
  # Listings

  ### Custom query params

  To set preloads or ordering for your listing you can call

      listings do
        listing do
          listing_query %{preload: [fragments: :creator], order: [{:asc, :sequence}]}
          # ...
        end
      end

  This will merge in your listing_query as the starting point for your queries

  """

  defmodule Listing do
    defstruct name: nil,
              query: %{},
              fields: [],
              filters: [],
              actions: [],
              selection_actions: [],
              child_listing: nil
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
    Module.put_attribute(__CALLER__.module, :ctx, "listings")
    listings(__CALLER__, block)
  end

  defp listings(_caller, block) do
    quote generated: true, location: :keep do
      Module.register_attribute(__MODULE__, :listings, accumulate: true)
      Module.put_attribute(__MODULE__, :brando_macro_context, :listings)
      unquote(block)
    end
  end

  defmacro listing(name, do: block) do
    do_listing(name, block)
  end

  defmacro listing(do: block) do
    do_listing(:default, block)
  end

  defp do_listing(name, block) do
    quote location: :keep,
          generated: true do
      Module.put_attribute(__MODULE__, :brando_macro_context, :listing)
      var!(brando_listing_fields) = []
      var!(brando_listing_query) = %{}
      var!(brando_listing_filters) = []
      var!(brando_listing_actions) = []
      var!(brando_listing_selection_actions) = []
      var!(brando_listing_child_listing) = nil
      unquote(block)

      named_listing =
        build_listing(
          unquote(name),
          var!(brando_listing_query),
          Enum.reverse(var!(brando_listing_fields)),
          var!(brando_listing_filters),
          var!(brando_listing_actions),
          var!(brando_listing_selection_actions),
          var!(brando_listing_child_listing)
        )

      Module.put_attribute(__MODULE__, :listings, named_listing)
    end
  end

  defmacro field(name, type, opts \\ []) do
    quote generated: true,
          location: :keep,
          bind_quoted: [name: name, type: type, opts: opts] do
      var!(brando_listing_fields) =
        List.wrap(build_field(name, type, opts)) ++ var!(brando_listing_fields)
    end
  end

  defmacro template(template, opts \\ []) do
    quote generated: true,
          location: :keep,
          bind_quoted: [template: template, opts: opts] do
      var!(brando_listing_fields) =
        List.wrap(build_template(template, opts)) ++ var!(brando_listing_fields)
    end
  end

  defmacro listing_query(query) do
    quote generated: true,
          location: :keep,
          bind_quoted: [query: query] do
      var!(brando_listing_query) = query
    end
  end

  defmacro child_listing(listing_name) do
    quote generated: true,
          location: :keep,
          bind_quoted: [listing_name: listing_name] do
      var!(brando_listing_child_listing) = listing_name
    end
  end

  defmacro filters(filters) do
    quote generated: true,
          location: :keep,
          bind_quoted: [filters: filters] do
      var!(brando_listing_filters) = filters
    end
  end

  defmacro actions(actions) do
    quote generated: true,
          location: :keep,
          bind_quoted: [actions: actions] do
      var!(brando_listing_actions) = actions
    end
  end

  defmacro selection_actions(actions) do
    quote generated: true,
          location: :keep,
          bind_quoted: [actions: actions] do
      var!(brando_listing_selection_actions) = actions
    end
  end

  def build_listing(
        name,
        query,
        fields,
        filters,
        actions,
        selection_actions,
        child_listing
      ) do
    %__MODULE__.Listing{
      name: name,
      query: query,
      fields: fields,
      filters: filters,
      actions: Enum.map(actions, &Enum.into(&1, %{})),
      selection_actions: Enum.map(selection_actions, &Enum.into(&1, %{})),
      child_listing: child_listing
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
