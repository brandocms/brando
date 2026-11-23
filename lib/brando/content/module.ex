defmodule Brando.Content.Module do
  @moduledoc """
  Ecto schema for the Villain Content Module schema

  A module can hold a setup for multiple blocks.

  ## Multi module

  A module can be setup as a multi module, meaning it can contain X other entries.

  If the entry template is not floating your boat, you can access the child entries directly
  from you main module's code. Each entry is a block, with its vars on it:

  ```
  {% for link in entries %}
    <h2>{{ link.vars.header_text }}</h2>
  {% endfor %}

  {{ content | renderless }}
  ```

  We include `{{ content | renderless }}` at the bottom to show the proper UI for the
  child entries in the admin area, but since it runs through the `renderless` filter,
  it will be excluded from rendering in the frontend.
  """

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "Module",
    singular: "module",
    plural: "modules",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext
  import Brando.Blueprint.Listings.Components.Children, only: [children_button: 1]
  import Brando.Blueprint.Listings.Components.Core

  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset
  alias Phoenix.LiveView.JS

  content_icon "blocks"

  @type t :: %__MODULE__{}

  @reserved_heex_assigns ~w(
    _heex_ctx block refs entries entries_with_meta content forloop
    identity configs globals navigation
    language locale entry render_context parser_module module_id
    links url request refs_field target target_ref form_id
  )

  identifier "[{{ entry.namespace | i18n }}] {{ entry.name | i18n }}"
  persist_identifier false

  @derived_fields ~w(
    id uid type name sequence namespace help_text multi color write_with_ai class code markdown_code refs vars svg deleted_at
    media_drop_child media_drop_ref
    version version_note source_module_id source_version acknowledged_version library_origin
    override_id
  )a
  @derive {Jason.Encoder, only: @derived_fields}

  trait :sequenced
  trait :soft_delete
  trait :timestamped
  trait :cast_polymorphic_embeds
  trait :ensure_uid
  trait :validate_var_keys
  trait :validate_media_drop
  trait :module_versioned

  attributes do
    # Lineage identity. Survives export/import, where name and namespace cannot:
    # both are i18n JSON maps, neither is unique, and both are editable.
    attribute :uid, :string, required: true

    attribute :type, :enum, values: [:liquid, :heex], default: :liquid
    attribute :name, :i18n_string, required: true
    attribute :namespace, :i18n_string, required: true
    attribute :help_text, :i18n_string, required: true
    attribute :class, :string, required: true
    attribute :code, :text, required: true
    attribute :svg, :text
    # A Liquid template for the module's Markdown, see `Brando.Villain.Markdown`.
    attribute :markdown_code, :text
    attribute :multi, :boolean
    attribute :color, :enum, values: [:blue, :emerald, :pink, :peach], default: :blue
    # Write with AI in the module's text blocks. Off unless turned on here:
    # every request is a paid call (see `BrandoAdmin.Components.Form.RichTextAI`).
    attribute :write_with_ai, :boolean, default: false
    # A multi module's blocks take dropped images and videos: each file makes
    # one block of the child module with this UID, with the file in its ref
    # `media_drop_ref` (`validate_media_drop/1`).
    attribute :media_drop_child, :string
    attribute :media_drop_ref, :string

    attribute :datasource, :boolean, default: false
    attribute :datasource_module, :string
    attribute :datasource_type, :enum, values: [:list, :single, :selection]
    attribute :datasource_query, :string

    attribute :version, :integer, default: 1
    attribute :version_note, :text
    attribute :source_module_id, :integer
    attribute :source_version, :integer
    attribute :acknowledged_version, :integer
    attribute :library_origin, :enum, values: [:local, :shared], default: :local, virtual: true
    attribute :update_available, :boolean, default: false, virtual: true
    attribute :override_id, :integer, virtual: true
  end

  relations do
    relation :children, :has_many,
      module: __MODULE__,
      on_replace: :delete_if_exists,
      foreign_key: :parent_id,
      preload_order: [asc: :sequence, asc: :id]

    relation :table_template, :belongs_to,
      module: Brando.Content.TableTemplate,
      on_replace: :delete_if_exists

    relation :parent, :belongs_to, module: __MODULE__, on_replace: :delete_if_exists

    relation :refs, :has_many,
      module: Brando.Content.Ref,
      on_replace: :delete,
      preload_order: [asc: :sequence, asc: :id],
      cast: true,
      sort_param: :sort_ref_ids,
      drop_param: :drop_ref_ids

    relation :vars, :has_many,
      module: Brando.Content.Var,
      on_replace: :delete,
      preload_order: [asc: :sequence, asc: :id],
      cast: true,
      sort_param: :sort_var_ids,
      drop_param: :drop_var_ids
  end

  listings do
    listing do
      query %{
        filter: %{parent_id: nil},
        preload: [
          children: %{
            module: __MODULE__,
            order: [asc: :sequence, asc: :id],
            hide_deleted: true
          }
        ],
        order: [{:asc, :namespace}, {:asc, :sequence}, {:desc, :inserted_at}]
      }

      filter label: t("Name"), key: "name"
      filter label: t("Namespace"), key: "namespace"
      filter label: t("Class"), key: "class"
      filter label: t("Code"), key: "code"

      # `JSCommands`, not `BrandoAdmin.Utils`: a `selection_action`'s event is built
      # during compilation of this schema, and `Utils` pulls in the translator and
      # `Phoenix.Component` — so this schema recompiled with the admin. See #2737.
      selection_action label: t("Export modules"),
                       event:
                         "export_modules"
                         |> JS.push()
                         |> BrandoAdmin.JSCommands.show_modal("#module-export-modal")

      selection_action label: t("Export DSL files"),
                       event:
                         "export_module_files"
                         |> JS.push()
                         |> BrandoAdmin.JSCommands.show_modal("#module-files-modal")

      child_listing name: :module_entries, schema: Brando.Content.Module
      component &__MODULE__.listing_row/1
    end

    listing :module_entries do
      component &__MODULE__.listing_child_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.field class="listing-module-icon" columns={2}>
      <div class="svg"><img :if={@entry.svg} src={"data:image/svg+xml;base64,#{@entry.svg}"} /></div>
    </.field>
    <.field class="listing-category" columns={3}>
      <div class="badge"><.i18n map={@entry.namespace} /></div>
    </.field>
    <.update_link class="listing-title" entry={@entry} columns={8}>
      <Brando.HTML.Icon.icon :if={@entry.datasource} name="database" class="xs listing-datasource-icon" />
      <.i18n map={@entry.name} />
      <:outside>
        <br />
        <small><.i18n map={@entry.help_text} /></small>
        <BrandoAdmin.Components.DefinitionFile.marker file={Brando.Content.Definition.Watcher.file(@entry.uid)} />
        <BrandoAdmin.Components.DefinitionFile.release_marker state={
          Brando.Content.Definitions.ReleaseStatus.state(@entry.uid)
        } />
      </:outside>
    </.update_link>
    <.children_button entry={@entry} fields={[:children]} />
    """
  end

  def listing_child_row(assigns) do
    ~H"""
    <.field class="listing-module-icon" columns={2}>
      <div class="svg"><img :if={@entry.svg} src={"data:image/svg+xml;base64,#{@entry.svg}"} /></div>
    </.field>
    <.field class="listing-category" columns={3}>
      <div class="badge"><.i18n map={@entry.namespace} /></div>
    </.field>
    <.update_link class="listing-title" entry={@entry} columns={9}>
      <Brando.HTML.Icon.icon :if={@entry.datasource} name="database" class="xs listing-datasource-icon" />
      <.i18n map={@entry.name} />
      <:outside>
        <br />
        <small><.i18n map={@entry.help_text} /></small>
        <BrandoAdmin.Components.DefinitionFile.marker file={Brando.Content.Definition.Watcher.file(@entry.uid)} />
        <BrandoAdmin.Components.DefinitionFile.release_marker state={
          Brando.Content.Definitions.ReleaseStatus.state(@entry.uid)
        } />
      </:outside>
    </.update_link>
    """
  end

  translations do
    context :naming do
      translate :singular, t("module")
      translate :plural, t("modules")
    end
  end

  factory %{
    class: "header middle",
    code: """
    <article data-v="text center" data-moonwalk-section>
      <div class="inner" data-moonwalk>
        <div class="text">
          {% ref refs.H2 %}
        </div>
      </div>
    </article>
    """,
    deleted_at: nil,
    help_text: "Help Text",
    name: "Heading",
    namespace: "general",
    refs: [
      %{
        "data" => %{
          "data" => %{
            "class" => nil,
            "id" => nil,
            "level" => 2,
            "text" => "Heading here"
          },
          "type" => "header"
        },
        "description" => "A heading",
        "name" => "H2",
        "uid" => "default-h2-ref"
      }
    ],
    vars: [],
    multi: false
  }

  # The "Legacy Content Wrapper" that the brando_108 upgrade migration makes
  # to hold the free-standing blocks of a Villain site, one per block in its
  # `content` ref. brando_108 finds it by this class and its "migration"
  # namespace, and brando_188 by the class alone. The class is what stays:
  # brando_125 keeps the namespace only under "en", and an admin may rename
  # either the module or its namespace.
  @legacy_wrapper_class "legacy-content"
  @legacy_wrapper_ref "content"

  @doc "The class of the Legacy Content Wrapper (see `legacy_wrapper?/1`)."
  def legacy_wrapper_class, do: @legacy_wrapper_class

  @doc """
  Whether `module` is the Legacy Content Wrapper, the module the brando_108
  upgrade migration wraps a Villain site's free-standing blocks in. Its
  blocks keep the content they were converted with, and nothing new is
  written with it.
  """
  @spec legacy_wrapper?(term()) :: boolean()
  def legacy_wrapper?(%{class: @legacy_wrapper_class}), do: true
  def legacy_wrapper?(_module), do: false

  @doc """
  Whether `module`'s ref `name` holds a ref of any type in a block. Only the
  Legacy Content Wrapper's `content` does: it is declared as a text ref, but
  holds each wrapped block as the type it was (picture, video, html, comment
  and so on), so that ref is never stale for its type.
  """
  @spec any_ref_type?(term(), String.t() | nil) :: boolean()
  def any_ref_type?(module, name), do: name == @legacy_wrapper_ref and legacy_wrapper?(module)

  @media_drop_ref_types ~w(media picture video)

  @doc """
  The ref types a `media_drop` ref may have: the ones that hold one image or
  one video.
  """
  def media_drop_ref_types, do: @media_drop_ref_types

  @doc """
  Validates `media_drop_child` and `media_drop_ref` when this change sets
  them (`media_drop_issue/2`), against the module's children, loaded here
  when the caller did not. A module not yet stored has none to check the
  child against, and is checked as far as it can be: a shared-library
  override copies the setting without the children. A definitions import
  passes `media_drop_checked: true`: its files were checked against each
  other when they were read, and may add the child or rename its ref in the
  same import. Turning `multi` off clears the setting. A stored setting gone stale is left for the module editor to
  show, and never blocks a save of another field.
  """
  def validate_media_drop(changeset, opts \\ []) do
    cond do
      Changeset.changed?(changeset, :media_drop_child) or Changeset.changed?(changeset, :media_drop_ref) ->
        module = Changeset.apply_changes(changeset)
        children = if opts[:media_drop_checked], do: nil, else: fn -> media_drop_children(changeset.data) end

        case media_drop_issue(module, children) do
          nil ->
            changeset

          {field, _message, keys} = issue ->
            Changeset.add_error(changeset, field, translate_media_drop_issue(issue), keys)
        end

      Changeset.changed?(changeset, :multi) and Changeset.get_field(changeset, :multi) != true ->
        Changeset.change(changeset, media_drop_child: nil, media_drop_ref: nil)

      true ->
        changeset
    end
  end

  # The module's children with their refs, nil for a module not yet stored.
  # Plain map patterns: the struct is defined after this function is compiled.
  defp media_drop_children(%{id: nil}), do: nil

  defp media_drop_children(module) do
    children = from(c in __MODULE__, where: is_nil(c.deleted_at), order_by: [asc: c.sequence, asc: c.id])

    module
    |> Brando.Repo.preload(children: {children, [:refs]})
    |> Map.fetch!(:children)
    |> Enum.reject(& &1.deleted_at)
    |> Brando.Repo.preload(:refs)
  end

  @doc """
  What is wrong with `module`'s `media_drop` (`media_drop_child`,
  `media_drop_ref` and `multi`) among its `children`, as `media_drop_problem/3`
  takes them; `children` may be a function returning them, called only when
  needed, and nil leaves the child unchecked. Returns `{field, message, keys}`,
  or nil when nothing is wrong or nothing is set.
  """
  def media_drop_issue(%{media_drop_child: nil, media_drop_ref: nil}, _children), do: nil

  def media_drop_issue(%{media_drop_child: child, media_drop_ref: ref} = module, children) do
    cond do
      is_nil(child) -> {:media_drop_child, gettext_noop("name the child module the dropped files create"), []}
      is_nil(ref) -> {:media_drop_ref, gettext_noop("name the ref of %{child} the dropped files go in"), [child: child]}
      module.multi != true -> {:media_drop_child, gettext_noop("needs a multi module"), []}
      true -> media_drop_target_issue(if(is_function(children, 0), do: children.(), else: children), child, ref)
    end
  end

  defp media_drop_target_issue(nil, _child, _ref), do: nil
  defp media_drop_target_issue(children, child, ref), do: media_drop_problem(children, child, ref)

  @doc """
  A `media_drop_issue/2` as English text, its keys filled in, for a
  definition file's error, worded in English as the other definition errors
  are.
  """
  def describe_media_drop_issue({_field, message, keys}),
    do: Enum.reduce(keys, message, fn {key, value}, text -> String.replace(text, "%{#{key}}", to_string(value)) end)

  @doc "A `media_drop_issue/2` as text in the current locale, its keys filled in, for the admin."
  def translate_media_drop_issue({_field, message, keys}), do: Gettext.gettext(Brando.Gettext, message, keys)

  @doc """
  What is wrong with a `media_drop` naming `child_uid` and `ref_name` among
  `children` (maps with `uid` and `refs`, each ref with `name` and `type`, or
  `data` holding the type): `{field, message, keys}`, or nil when nothing is.
  """
  def media_drop_problem(children, child_uid, ref_name) do
    with {:child, %{} = child} <- {:child, Enum.find(children, &(&1.uid == child_uid))},
         {:ref, %{} = ref} <- {:ref, Enum.find(child.refs, &(&1.name == ref_name))},
         false <- ref_type(ref) in @media_drop_ref_types do
      {:media_drop_ref, gettext_noop("ref %{ref} of %{child} is a %{type} ref, not a media, picture or video ref"),
       [child: child_uid, ref: ref_name, type: ref_type(ref)]}
    else
      {:child, nil} ->
        {:media_drop_child, gettext_noop("%{child} is not a child module of this module"), [child: child_uid]}

      {:ref, nil} ->
        {:media_drop_ref, gettext_noop("%{child} has no ref %{ref}"), [child: child_uid, ref: ref_name]}

      true ->
        nil
    end
  end

  defp ref_type(%{data: %{type: type}}), do: to_string(type)
  defp ref_type(%{type: type}), do: to_string(type)
  defp ref_type(_ref), do: nil

  @doc """
  Returns the list of reserved HEEx assign names that cannot be used as var keys.
  """
  def reserved_heex_assigns, do: @reserved_heex_assigns

  @doc """
  Validates that var keys in the changeset don't collide with reserved HEEx assigns.

  Only applies when the module type is `:heex`.
  """
  def validate_var_keys(changeset) do
    type = Changeset.get_field(changeset, :type)

    if type == :heex do
      vars = Changeset.get_field(changeset, :vars) || []

      collisions =
        vars
        |> Enum.map(& &1.key)
        |> Enum.filter(&(&1 in @reserved_heex_assigns))

      if collisions == [] do
        changeset
      else
        Changeset.add_error(
          changeset,
          :vars,
          "var keys conflict with reserved HEEx assigns: #{Enum.join(collisions, ", ")}"
        )
      end
    else
      changeset
    end
  end
end
