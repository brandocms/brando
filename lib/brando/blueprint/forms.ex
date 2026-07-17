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
  can override this by passing a 3-arity function to `redirect_on_save/1`:

      form do
        redirect_on_save &__MODULE__.my_custom_redirect/3
      end

      def my_custom_redirect(socket, _entry, _mutation_type) do
        Brando.RuntimeConfig.router_helpers().admin_live_path(socket, BrandoAdmin.PageListView)
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
        component :page_vars

  Image transformer:

  This creates a "dropbox" where you can drop or pick a bunch of images which
  then will be transformed into subforms with all the fields specified.

  Transformer subforms must target a `:has_many` or `:embeds_many` relation whose
  module is another Blueprint, and must use `cardinality: :many`. The style names
  one image or video asset on the related Blueprint, or one of each for mixed media:

      style: {:transformer, :logo}
      style: {:transformer, [:image, :video]}

  Brando validates the relation, nested fields, and asset types after the related
  schemas compile. A missing `default` creates a fresh related struct. An explicit
  default can be a map, a struct, or a two-argument callback receiving the parent
  entry and the uploaded asset (or `nil` when adding an empty entry).

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

  `client_listing/1` must be a one-argument function component:

        def client_listing(assigns) do
          ~H\"""
          <div>
            <div>
              Name: <%= @entry.name %>
            </div>
          </div>
          \"""
        end


  ## Input types

  ## Common input options

  ### `hidden`: Conditionally hide an input

  You can hide any input based on a static value, another field's value, or custom logic.

  #### Option shapes

      - `hidden: true | false`
      - `hidden: {:field_name, expected_value}`
      - `hidden: fn form -> boolean end`

  #### Example

      input :type, :radios,
        options: [
          %{value: :full_case, label: "Full case"},
          %{value: :external_link, label: "External link"}
        ]

      input :external_link, :text,
        hidden: {:type, :full_case}

      input :client_quote, :textarea,
        hidden: fn form ->
          form[:type].value != :full_case
        end

  For tuple rules, atom/string values are treated as equivalent (`:full_case` matches `"full_case"`).
  The rule is evaluated whenever the form re-renders.

  ### `ai`: Generate text with ReqLLM

  Add an AI action button to `:text`, `:textarea`, and `:rich_text` inputs. Clicking the button
  sends a server-side request and replaces the field value with generated text.

  #### Field options

      input :meta_description, :textarea,
        ai: [
          prompt: "Write a succinct meta description based on title and intro",
          context: [:title, :intro]
        ]

  For `:rich_text` fields, prompt the model to return HTML (not Markdown),
  since the editor stores HTML.

  #### AI options

      - `prompt` (required): Instruction sent to the model
      - `context` (optional): List of fields to append as context.
        Supports regular fields and `:blocks` (rendered block content)
      - `model` (optional): Model in `"provider:model"` format.
        If omitted, `Brando.AI` uses its configured `:default_model`
      - `api_key` (optional): Per-field/provider key override
      - `temperature`, `max_tokens`, `top_p`, `presence_penalty`, `frequency_penalty`,
        `tool_choice`, `tools`, `system_prompt`, `provider_options`,
        `receive_timeout`, `thinking_timeout` (optional): forwarded to ReqLLM

  #### Configuration

  Configure AI defaults in your app config:

      config :brando, Brando.AI,
        enabled: true,
        default_model: "openai:gpt-4o-mini",
        providers: [
          openai: [api_key: System.get_env("OPENAI_API_KEY")]
        ],
        default_opts: [temperature: 0.4]

  Optional per-field defaults:

      config :brando, Brando.AI,
        fields: [
          summary: [prompt: "Summarize title and intro", context: [:title, :intro]],
          teaser: [prompt: "Write a short teaser from title and intro", context: [:title, :intro]]
        ]

  Trait-provided defaults:
    Traits may provide field defaults before generic `fields` fallback.
    For `Brando.Trait.Meta`, configure `meta_title`/`meta_description` defaults
    on the blueprint:

      trait :meta,
        ai: [
          meta_title: [prompt: "Write SEO title from title", context: [:title]],
          meta_description: [prompt: "Write SEO description from title and blocks", context: [:title, :blocks]]
        ]

  The AI action only appears when:
    - the input has `ai: [...]`
    - or a matching trait / `Brando.AI` fallback exists
    - Brando AI is enabled/configured for that provider/model

  #### Meta trait fields

  `meta_title` and `meta_description` are rendered in the Meta drawer.
  You can configure AI for these fields either by:
    - declaring form inputs with `ai: [...]`
    - setting `trait :meta, ai: [...]`

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

  ```
  input :project_categories, :multi_select,
    options: &__MODULE__.get_categories/2,
    relation_key: :category_id,
    relation: :category,
    resetable: true,
    wrapped_labels: true,
    label: t("Categories")
  ```

  For `:has_many` relations, the join schema must have `@allow_mark_as_deleted true` set.

  To enable drag-and-drop reordering of selected items, the join schema must have `Brando.Trait.Sequenced`,
  and the relation must have `sort_param` configured:

  ```
  relation :project_categories, :has_many,
    module: Projects.ProjectCategory,
    preload_order: [{:asc, :sequence}],
    sort_param: :sort_category_ids,
    drop_param: :drop_category_ids,
    on_replace: :delete_if_exists,
    cast: true
  ```

  ### `rich_text`: Rich text editor (TipTap)

  #### Options

      - `extensions`: List of extensions to enable. Defaults to `all`.
          ```
          input :rich_text, :rich_text,
            label: "Rich text",
            extensions: ["p", "h2", "bold", "link", "color"]
          ```

  ### `select`: Select field

  ```
  input :client_id, :select,
    options: &__MODULE__.get_clients/2,
    update_relation: {:client, &__MODULE__.get_client/1},
    resetable: true,
    label: t("Client")
  ```

  #### Options

      - `options` - List of options or a function returning options.
      - `update_relation` - Tuple of `{relation_field, fetcher_function}` to update a relation.
      - `resetable` - Allow resetting the value to nil.
      - `narrow` - Use a narrower modal.
      - `inline` - Show options inline instead of in a modal.
      - `filter` - Show filter input in modal. Defaults to `true`.
      - `allow_custom` - Allow entering custom values not in the options list.
          When enabled, shows a "Custom value" input in the modal and displays
          custom values in the select label instead of "No selection".
          ```
          input :aspect_ratio, :select,
            options: [{"16:9", "16:9"}, {"4:3", "4:3"}],
            allow_custom: true,
            label: t("Aspect Ratio")
          ```

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

  @doc """
  Lists every top-level field name in a form.
  """
  @spec list_fields(struct()) :: [atom()]
  def list_fields(%Forms.Form{tabs: tabs}) do
    for tab <- tabs,
        %Forms.Fieldset{fields: inputs} <- tab.fields,
        input <- inputs do
      input.name
    end
  end

  @doc """
  Lists top-level fields of a specific input type.
  """
  @spec list_fields(struct(), :multi_select | :select) :: [atom()]
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

  @doc """
  Returns the tab containing `field`.

  Foreign-key error fields such as `:creator_id` resolve to an input named
  `:creator`. Exact field names take precedence, and an unknown field falls back
  to the first tab.
  """
  @spec get_tab_for_field(atom() | String.t(), struct()) :: String.t() | nil
  def get_tab_for_field(field, %Forms.Form{tabs: tabs}) do
    find_tab_for_field(tabs, field) ||
      find_tab_for_field(tabs, foreign_key_base(field)) ||
      tabs |> List.first() |> Map.get(:name)
  end

  @doc """
  Returns the form element for `field`, including foreign-key-normalized fields.

  Exact field names take precedence over stripping a trailing `_id` suffix.
  """
  @spec get_field(atom() | String.t(), struct()) :: struct() | nil
  def get_field(field, %Forms.Form{tabs: tabs}) do
    find_form_field(tabs, field) || find_form_field(tabs, foreign_key_base(field))
  end

  defp find_tab_for_field(tabs, field) do
    Enum.find_value(tabs, fn tab ->
      if find_form_field([tab], field), do: tab.name
    end)
  end

  defp find_form_field(tabs, field) do
    Enum.find_value(tabs, fn tab ->
      Enum.find_value(tab.fields, fn
        %Forms.Fieldset{fields: inputs} -> Enum.find(inputs, &field_matches?(&1, field))
        _other -> nil
      end)
    end)
  end

  defp field_matches?(%{name: name}, field), do: to_string(name) == to_string(field)
  defp field_matches?(%{field: subform_field}, field), do: to_string(subform_field) == to_string(field)
  defp field_matches?(_form_element, _field), do: false

  defp foreign_key_base(field) do
    field
    |> to_string()
    |> String.trim_trailing("_id")
  end
end
