defmodule Brando.Blueprint.Forms do
  @moduledoc """
  # Form

  ## Default params

  You can supply `default_params` if you want the form to be
  prepopulated with your own defaults when creating a new entry:

      form do
        default_params: %{status: :draft}
        # ...
      end


  ## Query

  Default query is `%{matches: %{id: id}}`, but if you to customize:

      forms do
        form do
          query &__MODULE__.query_with_preloads/1
        end
      end

      def query_with_preloads(id) do
        %{matches: %{id: id}, preload: [:illustrators]}
      end

  If you override the default query, you must supply ALL preloads -- this includes `alternate_entries`
  as well as images, videos and files.


  ## Redirect after save

  By default, we will redirect to the List view of your blueprint. You
  can override this by using `redirect_on_save/1`:

      form do
        redirect_on_save &__MODULE__.my_custom_redirect/3
      end

      def my_custom_redirect(socket, _entry, _mutation_type) do
        Brando.routes().admin_live_path(socket, BrandoAdmin.PageListView)
      end


  ## Subforms

  Renders a sub form

  ## Example

  Regular inline form set:

      fieldset do
        size :full
        inputs_for :items, [
          label: t("Items"),
          style: :inline,
          cardinality: :many,
          size: :full,
          default: %Item{}
        ] do
          input :status, :status, compact: true, label: :hidden
          input :title, :text, label: t("Title", Item)
          input :key, :text, monospace: true, label: t("Key", Item)
          input :url, :text, monospace: true, label: t("URL", Item)
          input :open_in_new_window, :toggle, label: t("New window?", Item)
        end
      end

  Custom component:

      inputs_for :vars do
        label t("Page variables")
        component BrandoAdmin.Components.Pages.PageVars

  Image transformer:

  This creates a "dropbox" where you can drop or pick a bunch of images which
  then will be transformed into subforms with all the fields specified.

  For instance, if you have a `Project` that has many `Client`s, and you wish to upload
  a bunch of their logos before adding the rest of the information, you could start by
  adding a relation to your `Project` blueprint:

      relations do
        relation :clients, :has_many, module: MyApp.Projects.Client, on_replace: :delete, cast: true
      end

  Then we add a corresponding relation at the other end (meaning the `Client` blueprint)

      relations do
        relation :project, :belongs_to, module: MyApp.Projects.Project
      end

  Finally we add the transformer input to our project form:

      forms do
        form do
          # ...
          fieldset do
            size :full
            inputs_for :clients,
              label: t("Clients"),
              cardinality: :many,
              style: {:transformer, :logo},
              default: %Client{} do
              # add the Client schemas attributes
              input :logo, :image
              input :name, :text, placeholder: "Client Name"
              input :phone, :text, placeholder: "+47 900 00 000"
              input :email, :text, placeholder: "my@email.co"
              input :creator_id, :hidden # <-- if the client schema has a creator
            end
          end
        end
      end

  You can also specify a callback function for the `default` key:

        default: &__MODULE__.default_client/2

        def default_client(_entry, image) do
          orientation = Brando.Images.get_image_orientation(image)
          %Client{name: orientation}
        end

  As well as a custom listing:

        listing: &__MODULE__.client_listing/1

  `client_listing/1` should then be a function component:

        def asset_listing(assigns) do
          ~H\"""
          <div>
            <div>
              Name: <%= @entry.name %>
            </div>
          </div>
          \"""
        end


  ## Input types

  ### `blocks`: Block editor

  #### Options

      - `palette_namespace`: Show palettes from this namespace in containers
      - `template_namespace`: Show templates from this namespace as starting
        points when presented with a blank editor
      - `module_set`: Show modules from this set as starting
        points when presented with a blank editor

  ### `color`: Color picker

  #### Options

      - `opacity`: `bool` — Allow setting opacity
      - `picker`: `bool` — Allow picking custom colors. You could set this to false
         and use a `palette_id` to only allow picking from a locked set of colors
      - `palette_id`: `int` — Allow to pick from colors in this palette

  ### `entries`: Related entries

  #### Options

      - `for`: List of tuples with {module, listing_opts}. I.e:
        ```elixir
        for: [{__MODULE__, %{preload: [], order: "asc title", status: :published}}],
        ```
      - `filter_language`: `bool` — Only show entries in same language as main entry

  ### `multi_select`: Multiple select field

  ### `rich_text`: Rich text editor (TipTap)

  ### `select`: Select field

  ### `slug`: Slug field

  #### Options

      - `source` - the field we want to create a slug from.
          ```
          input :slug, :slug, source: :title
          ```

          Can also be a list for composite slugs:
          ```
          input :slug, :slug, source: [:location, :position]
          ```

      - `camel_case: true` - Returns slug as `camelCase` instead of `this-type-of-slug`.
      - `show_url: true` - Runs the applied changeset through the schema's `__absolute_url__`
        function and displays the resulting url.

  ### `status`: Status field

  ### `text`: Standard form element
  """
  alias Brando.Blueprint.Forms

  defmacro form_query(_) do
    raise Brando.Exception.BlueprintError,
      message: "form_query/1 is deprecated. use query/1 instead"
  end

  def list_fields(%Forms.Form{tabs: tabs}) do
    for tab <- tabs,
        %Forms.Fieldset{fields: inputs} <- tab.fields,
        input <- inputs do
      input.name
    end
  end

  def list_fields(%Forms.Form{tabs: tabs}, :select) do
    for tab <- tabs,
        %Forms.Fieldset{fields: inputs} <- tab.fields,
        %{type: type, name: name} when type == :select <- inputs do
      name
    end
  end

  def list_fields(%Forms.Form{tabs: tabs}, :multi_select) do
    for tab <- tabs,
        %Forms.Fieldset{fields: inputs} <- tab.fields,
        %{type: type, name: name} when type == :multi_select <- inputs do
      name
    end
  end

  def get_tab_for_field(field, %Forms.Form{tabs: tabs}) do
    tab =
      for tab <- tabs,
          %Forms.Fieldset{fields: inputs} <- tab.fields do
        find_field(inputs, field) && tab.name
      end
      |> Enum.filter(&is_binary(&1))
      |> List.first()

    tab || tabs |> List.first() |> Map.get(:name)
  end

  def get_field(field, %Forms.Form{tabs: tabs}) do
    for tab <- tabs,
        %Forms.Fieldset{fields: inputs} <- tab.fields do
      find_field_normalized(inputs, field)
    end
    |> Enum.reject(&is_nil(&1))
    |> List.first()
  end

  defp find_field(inputs, field) do
    Enum.find(inputs, fn
      %{name: name, type: :image} -> "#{name}_id" == to_string(field)
      %{name: name, type: :file} -> "#{name}_id" == to_string(field)
      %{name: name} -> name == field
      %{field: subform_field} -> subform_field == field
    end)
  end

  defp find_field_normalized(inputs, field) do
    Enum.find(inputs, fn
      %{name: name} ->
        to_string(name) == String.replace(to_string(field), "_id", "")

      %{field: subform_field} ->
        to_string(subform_field) == String.replace(to_string(field), "_id", "")
    end)
  end
end
