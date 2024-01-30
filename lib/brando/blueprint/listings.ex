defmodule Brando.Blueprint.Listings do
  @moduledoc """
  # Listings

  ### Listing/row component

  Set your own component for rendering a listing row:

      listings do
        listing do
          component &__MODULE__.list_row/1
          # ...
        end
      end

      def listing_row(assigns) do
        ~H\"""
        <.cover image={@entry.cover} columns={2} size={:smallest} padded />
        <.update_link entry={@entry} columns={6}>
          <%= @entry.title %>
          <:outside>
            <%= if @entry.category do %>
              <br />
              <small class="badge"><%= @entry.category.name %></small>
            <% end %>
          </:outside>
        </.update_link>
        <.url entry={@entry} />
        \"""
      end

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
              sortable: true,
              default_actions: true,
              actions: [],
              selection_actions: [],
              exports: [],
              child_listing: nil,
              component: nil
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

  defmodule Export do
    defstruct name: nil,
              label: nil,
              type: :csv,
              fields: [],
              description: nil,
              query: %{},
              after_export: nil
  end

  defmacro __using__(_) do
    quote do
      import Brando.Blueprint.Listings
      import Brando.Blueprint.Translations
    end
  end

  defmacro listings(do: block) do
    Module.put_attribute(__CALLER__.module, :ctx, "listings")
    listings(__CALLER__, block)
  end

  defp listings(_caller, block) do
    quote generated: true, location: :keep do
      Module.register_attribute(__MODULE__, :listings, accumulate: true, persist: true)
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
      var!(brando_listing_exports) = []
      var!(brando_listing_child_listing) = nil
      var!(brando_listing_component) = nil
      var!(brando_listing_default_actions) = true
      var!(brando_listing_sortable) = true

      unquote(block)

      named_listing =
        build_listing(
          unquote(name),
          var!(brando_listing_query),
          Enum.reverse(var!(brando_listing_fields)),
          var!(brando_listing_filters),
          var!(brando_listing_actions),
          var!(brando_listing_selection_actions),
          var!(brando_listing_child_listing),
          var!(brando_listing_default_actions),
          var!(brando_listing_sortable),
          var!(brando_listing_exports),
          var!(brando_listing_component)
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

  defmacro sortable(boolean) do
    quote generated: true,
          location: :keep,
          bind_quoted: [boolean: boolean] do
      var!(brando_listing_sortable) = boolean
    end
  end

  defmacro export(export_name, opts) do
    quote generated: true,
          location: :keep,
          bind_quoted: [export_name: export_name, opts: opts] do
      var!(brando_listing_exports) = [
        Map.merge(%Brando.Blueprint.Listings.Export{name: export_name}, Enum.into(opts, %{}))
        | var!(brando_listing_exports)
      ]
    end
  end

  defmacro filters(filters) do
    quote generated: true,
          location: :keep,
          bind_quoted: [filters: filters] do
      var!(brando_listing_filters) = filters
    end
  end

  defmacro component(component) do
    quote generated: true,
          location: :keep,
          bind_quoted: [component: component] do
      var!(brando_listing_component) = component
    end
  end

  defmacro actions(actions, opts \\ []) do
    quote generated: true,
          location: :keep,
          bind_quoted: [actions: actions, opts: opts] do
      processed_actions =
        Enum.map(actions, fn action ->
          event =
            if is_binary(action[:event]) do
              Phoenix.LiveView.JS.push(action[:event])
            else
              action[:event]
            end

          Keyword.replace(action, :event, event)
        end)

      default_actions = Keyword.get(opts, :default_actions, true)

      var!(brando_listing_default_actions) = default_actions
      var!(brando_listing_actions) = processed_actions
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
        child_listing,
        default_actions,
        sortable,
        exports,
        component
      ) do
    %__MODULE__.Listing{
      name: name,
      query: query,
      fields: fields,
      filters: filters,
      actions: Enum.map(actions, &Enum.into(&1, %{})),
      selection_actions: Enum.map(selection_actions, &Enum.into(&1, %{})),
      child_listing: child_listing,
      default_actions: default_actions,
      sortable: sortable,
      exports: exports,
      component: component
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
