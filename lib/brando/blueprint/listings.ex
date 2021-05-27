defmodule Brando.Blueprint.Listings do
  @moduledoc """
  ### Listings
  """

  defmodule Listing do
    defstruct name: nil,
              label: nil,
              query: %{},
              fields: [],
              actions: [],
              selection_actions: []
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

  defmacro listing(name, do: block) do
    do_listing(name, block)
  end

  defmacro listing(do: block) do
    do_listing(:default, block)
  end

  defp do_listing(name, block) do
    quote location: :keep,
          generated: true do
      var!(brando_listing_fields) = []
      var!(brando_listing_query) = %{}
      var!(brando_listing_label) = nil
      var!(brando_listing_actions) = []
      var!(brando_listing_selection_actions) = []
      unquote(block)

      named_listing =
        build_listing(
          unquote(name),
          var!(brando_listing_query),
          var!(brando_listing_label),
          Enum.reverse(var!(brando_listing_fields)),
          var!(brando_listing_actions),
          var!(brando_listing_selection_actions)
        )

      Module.put_attribute(__MODULE__, :listings, named_listing)
    end
  end

  defmacro listing_field(name, type, opts \\ []) do
    quote generated: true,
          location: :keep,
          bind_quoted: [name: name, type: type, opts: opts] do
      var!(brando_listing_fields) =
        List.wrap(build_field(name, type, opts)) ++ var!(brando_listing_fields)
    end
  end

  defmacro listing_template(template, opts \\ []) do
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

  defmacro listing_label(label) do
    quote generated: true,
          location: :keep,
          bind_quoted: [label: label] do
      var!(brando_listing_label) = label
    end
  end

  defmacro listing_actions(actions) do
    quote generated: true,
          location: :keep,
          bind_quoted: [actions: actions] do
      var!(brando_listing_actions) = actions
    end
  end

  defmacro listing_selection_actions(actions) do
    quote generated: true,
          location: :keep,
          bind_quoted: [actions: actions] do
      var!(brando_listing_selection_actions) = actions
    end
  end

  def build_listing(name, query, label, fields, actions, selection_actions) do
    %__MODULE__.Listing{
      name: name,
      label: label,
      query: query,
      fields: fields,
      actions: actions,
      selection_actions: selection_actions
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
