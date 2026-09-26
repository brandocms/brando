defmodule BrandoAdmin.Components.Form.Translation do
  @moduledoc """
  The entry form's side of synchronized translations (`Brando.Translations`).

  Opening a synchronized translation loads its pending version into the form
  as unsaved changes, through the same restore path as recovery copies, and
  lists the work it holds: text to translate or review, values updated from
  the source, links waiting for a translation. The editor marks reviewed text
  with a checkbox inside the main form, so the choice survives reconnects and
  reaches the save. The save resolves only the work of the version the editor
  loaded (`Brando.Translations.target_saved/3`).

  State lives in the Form's `:translation` assign, `nil` for entries outside a
  synchronized group.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias Brando.Drafts.Modules
  alias Brando.Drafts.Params
  alias Brando.Translations
  alias BrandoAdmin.Components.Form.Drafts

  @doc "Assigns the translation state of the form's entry."
  def assign_state(%{assigns: %{schema: schema, entry: %{id: id} = entry}} = socket) when not is_nil(id) do
    case Translations.editor_state(schema, id) do
      nil ->
        state = if Translations.synchronized?(schema), do: unlinked(schema, entry, socket.assigns.current_user)
        Phoenix.Component.assign(socket, :translation, state)

      state ->
        previous = socket.assigns[:translation]

        state = build(schema, socket.assigns.entry, state, previous, socket.assigns.current_user)

        state =
          case socket.assigns[:translation_acknowledged] do
            paths when is_list(paths) and state.acknowledged == [] -> %{state | acknowledged: paths}
            _ -> state
          end

        socket
        |> Phoenix.Component.assign(:translation, state)
        |> Phoenix.Component.assign(:translation_acknowledged, nil)
    end
  end

  def assign_state(socket), do: Phoenix.Component.assign(socket, :translation, nil)

  # A synchronized schema's entry that has no translations yet: it becomes the
  # source when the first one is created.
  defp unlinked(schema, entry, user) do
    taken = [to_string(entry.language) | Translations.alternate_languages(schema, entry.id)]

    %{
      schema: schema,
      entry_id: entry.id,
      role: :unlinked,
      synchronized?: false,
      language: to_string(entry.language),
      source: nil,
      members: [],
      missing_languages: languages_except(schema, taken),
      can_create?: Brando.Authorization.Boundary.authorize(user, :create, schema) == :ok,
      pending: nil,
      payload: nil,
      items: [],
      structure_changed?: false,
      applied_version_id: nil,
      acknowledged: [],
      stale?: false
    }
  end

  defp build(schema, entry, state, previous, user) do
    %{member: member, source: source, pending: pending} = state
    entry_id = entry.id
    payload = pending && Translations.decode_payload(pending)

    %{
      schema: schema,
      entry_id: entry_id,
      role: member.role,
      synchronized?: member.synchronized,
      language: member.language,
      source: source && Map.put(source, :url, admin_url(schema, source.id)),
      members: members(schema, member.group_id),
      missing_languages: missing_languages(schema, member.group_id, source),
      can_create?: Brando.Authorization.Boundary.authorize(user, :create, schema) == :ok,
      pending: pending,
      payload: payload,
      items: items(schema, pending, payload),
      structure_changed?: payload != nil and structure(payload, schema) != structure(entry, schema),
      # The version whose changes are in the form. Kept across refreshes of
      # the same entry, so a reconnecting form does not apply it twice.
      applied_version_id: previous && previous.entry_id == entry_id && previous.applied_version_id,
      acknowledged: (previous && previous.entry_id == entry_id && previous.acknowledged) || [],
      stale?: false
    }
  end

  defp members(schema, group_id) do
    for member <- Translations.list_members(group_id) do
      %{
        language: member.language,
        role: member.role,
        synchronized?: member.synchronized,
        entry_id: member.entry_id,
        url: admin_url(schema, member.entry_id),
        open: open_count(member)
      }
    end
  end

  defp open_count(%{role: :target, synchronized: true, id: id}) do
    case Translations.current_pending_for_member(id) do
      nil -> 0
      version -> Enum.count(version.work_items, &is_nil(&1.resolved_at))
    end
  end

  defp open_count(_member), do: 0

  # Languages without a version in the group, or linked to the source as an
  # existing, independent alternate — those are not joined to the group.
  defp missing_languages(schema, group_id, source) do
    members = group_id |> Translations.list_members() |> Enum.map(& &1.language)
    alternates = if source, do: Translations.alternate_languages(schema, source.id), else: []
    languages_except(schema, members ++ alternates)
  end

  defp languages_except(schema, taken) do
    for value <- Ecto.Enum.values(schema, :language), to_string(value) not in taken do
      code = to_string(value)
      %{code: code, label: language_label(code)}
    end
  end

  # Block and row membership, order and nesting. A source that only moves or
  # removes blocks raises no work item, but the translation still changes.
  defp structure(entry, schema) do
    for {path, :structure, value} <- Brando.Translations.Sync.flatten_entry(entry, schema), do: {path, value}
  rescue
    _ -> nil
  end

  @doc "Whether the entry is a synchronized translation, whose structure and shared values follow its source."
  def locked?(%{role: :target, synchronized?: true}), do: true
  def locked?(_state), do: false

  @doc "Whether the entry is the source of a translation group."
  def source?(%{role: :source}), do: true
  def source?(_state), do: false

  @doc "The admin URL of the source entry, for a translation."
  def source_url(%{role: :target, source: %{url: url}}), do: url
  def source_url(_state), do: nil

  @doc """
  What a synchronized translation may not edit in the form, as CSS selectors
  for `Brando.TranslationWork`: `inert` inputs (source-controlled fields,
  assets, source-controlled subform fields) and `structure` subforms, whose
  rows follow the source. The save check enforces the same on the server.
  """
  def locks(%{role: :target, synchronized?: true, schema: schema}, form_name) do
    config = schema.__translatable_config__()

    assets =
      for %{type: type, name: name} <- Brando.Blueprint.Assets.__assets__(schema),
          type in [:image, :video, :file, :gallery],
          do: name

    fields =
      Enum.flat_map(Enum.uniq(config.source_controlled_fields ++ assets), fn name ->
        [~s([name="#{form_name}[#{name}]"]), ~s([name="#{form_name}[#{name}_id]"])]
      end)

    subform_fields =
      for {subform, names} <- Map.get(config, :source_controlled_subform_fields, %{}), name <- names do
        ~s([name^="#{form_name}[#{subform}]["][name$="][#{name}]"])
      end

    structure =
      for %{type: type, name: name, opts: opts} <- Brando.Blueprint.Relations.__relations__(schema),
          type in [:has_many, :embeds_many],
          type == :embeds_many or Map.get(opts, :cast) == true,
          module = opts[:module],
          is_atom(module) and module not in [:blocks, :alternates],
          :uid in module.__schema__(:fields),
          do: ~s([data-sortable-id="#{form_name}[#{name}]-sortable"])

    %{inert: fields ++ subform_fields, structure: structure}
  end

  def locks(_state, _form_name), do: %{inert: [], structure: []}

  @doc "Whether the form should load the pending version now."
  def apply?(%{translation: %{pending: %{id: id}, applied_version_id: applied}}) when applied != id, do: true
  def apply?(_assigns), do: false

  @doc """
  Builds the changeset that puts the pending version into the form, on top of
  the saved entry. Returns `{:ok, changeset, socket}` with the version marked
  as applied, or `:error` when the version cannot be applied.
  """
  def restore_changeset(socket) do
    %{schema: schema, entry: entry, form_blueprint: blueprint, current_user: user, translation: state} =
      socket.assigns

    payload = state.payload

    blocks =
      Map.new(blueprint.blocks, fn field ->
        {to_string(field.name), Params.snapshot(Map.get(payload, :"entry_#{field.name}") || [])}
      end)

    transformers =
      Map.new(blueprint.transformers, fn {name, _, _} ->
        {to_string(name), Params.snapshot(Map.get(payload, name) || [])}
      end)

    draft = %{
      format_version: 1,
      schema_version: Brando.Blueprint.Snapshot.get_current_version(schema),
      base_fingerprint: Brando.Drafts.fingerprint(entry),
      payload: %{
        "main" => Drafts.main_params(socket, Ecto.Changeset.change(payload)),
        "blocks" => blocks,
        "transformers" => transformers,
        "modules" => Modules.manifest(blocks)
      }
    }

    case Brando.Drafts.Restore.prepare(draft, entry, schema, user, accept_conflict: true, compatible_only: true) do
      {:ok, changeset, _issues} ->
        state = %{state | applied_version_id: state.pending.id}
        {:ok, changeset, Phoenix.Component.assign(socket, :translation, state)}

      _ ->
        :error
    end
  end

  @doc "The pending version the form holds, for the save."
  def version_id(%{translation: %{applied_version_id: id}}) when is_integer(id), do: id
  def version_id(_assigns), do: nil

  @doc "Records the reviewed paths from the main form's parameters."
  # A reconnect replays the form's params, which can arrive before the
  # translation state is rebuilt; they are kept until it is.
  def put_acknowledged(socket, %{"translation_review" => _} = params) do
    paths =
      case params do
        %{"translation_review" => %{"acknowledged" => paths}} when is_list(paths) -> Enum.filter(paths, &is_binary/1)
        _ -> []
      end

    case socket.assigns[:translation] do
      %{} = state -> Phoenix.Component.assign(socket, :translation, %{state | acknowledged: paths})
      nil -> Phoenix.Component.assign(socket, :translation_acknowledged, paths)
    end
  end

  def put_acknowledged(socket, _params), do: socket

  @doc "What the save reports to `Brando.Translations.target_saved/3`."
  def review(%{translation: %{} = state} = assigns),
    do: %{version_id: version_id(assigns), acknowledged: state.acknowledged}

  def review(_assigns), do: nil

  ## Work items

  defp items(_schema, nil, _payload), do: []

  defp items(schema, pending, payload) do
    labels = field_labels(schema)
    blocks = block_index(schema, payload)

    pending.work_items
    |> Enum.filter(&is_nil(&1.resolved_at))
    |> Enum.sort_by(&{kind_order(&1.kind), &1.path})
    |> Enum.map(fn item ->
      target = target(item.path, blocks)

      %{
        path: item.path,
        kind: item.kind,
        label: label(item.path, target, labels),
        target: target
      }
    end)
  end

  defp kind_order(:translate), do: 0
  defp kind_order(:review), do: 1
  defp kind_order(:shared_update), do: 2
  defp kind_order(:awaiting_translation), do: 3

  # Where a work item's path points in the form: a field, a block (by uid) or a
  # subform row.
  defp target(path, blocks) do
    case String.split(path, "/") do
      ["entry_" <> _field, identity | rest] ->
        case blocks[identity] do
          nil -> {:field, path}
          block -> {:block, block.uid, block.module_name, rest}
        end

      [field] ->
        {:field, field}

      [subform, uid, field] ->
        {:row, subform, uid, field}

      _ ->
        {:field, path}
    end
  end

  defp block_index(schema, payload) do
    fields =
      if function_exported?(schema, :__blocks_fields__, 0),
        do: Enum.map(schema.__blocks_fields__(), &:"entry_#{&1.name}"),
        else: []

    fields
    |> Enum.flat_map(fn field ->
      case Map.get(payload, field) do
        joins when is_list(joins) -> Enum.map(joins, & &1.block)
        _ -> []
      end
    end)
    |> Enum.flat_map(&walk/1)
    |> Map.new(fn block -> {block.sync_uid || block.uid, %{uid: block.uid, module_name: module_name(block)}} end)
  end

  defp walk(nil), do: []

  defp walk(block) do
    children = if is_list(block.children), do: block.children, else: []
    [block | Enum.flat_map(children, &walk/1)]
  end

  # A block the pending version added has no module preloaded; its name is
  # looked up by id.
  defp module_name(%{module: %{name: name}}), do: localized(name)

  defp module_name(%{module_id: id} = block) when is_integer(id) do
    case Brando.Content.fetch_module(id, block.module_origin || :local) do
      %{name: name} -> localized(name)
      _ -> gettext("Block")
    end
  end

  defp module_name(_block), do: gettext("Block")

  defp localized(name) when is_map(name),
    do: name[Gettext.get_locale(Brando.Gettext)] || name["en"] || name |> Map.values() |> List.first()

  defp localized(name) when is_binary(name), do: name
  defp localized(_name), do: gettext("Block")

  defp label(_path, {:block, _uid, module_name, rest}, _labels), do: Enum.join([module_name | block_part(rest)], " › ")

  defp label(_path, {:row, subform, _uid, field}, labels),
    do: "#{labels[subform] || humanize(subform)} › #{labels[field] || humanize(field)}"

  defp label(_path, {:field, field}, labels), do: labels[field] || humanize(field)

  defp block_part(["refs", name, "text"]), do: [humanize(name)]
  defp block_part(["refs", name, "media"]), do: [humanize(name), gettext("media")]
  defp block_part(["refs", name, "gallery" | _]), do: [humanize(name), gettext("gallery")]
  defp block_part(["refs", name, field]), do: [humanize(name), humanize(field)]
  defp block_part(["vars", key, "media"]), do: [humanize(key), gettext("media")]
  defp block_part(["vars", key | _]), do: [humanize(key)]
  defp block_part(["rows", _row, "vars", key | _]), do: [gettext("Table"), humanize(key)]
  defp block_part(["identifiers" | _]), do: [gettext("Related entries")]
  defp block_part(["identifier_metas" | _]), do: [gettext("Related entries")]
  defp block_part(_rest), do: []

  # Labels from the form, translated in the schema's domain, as the inputs
  # show them.
  defp field_labels(schema) do
    naming = schema.__naming__()
    domain = String.downcase("#{naming.domain}_#{naming.schema}")
    gettext_module = schema.__modules__().gettext

    case schema.__form__() do
      %{tabs: tabs} ->
        for tab <- tabs, fieldset <- tab.fields, input <- fieldset.fields, reduce: %{} do
          acc ->
            acc
            |> put_label(input, gettext_module, domain)
            |> put_sub_labels(input, gettext_module, domain)
        end

      _ ->
        %{}
    end
  end

  defp put_label(acc, %{name: name} = input, gettext_module, domain) do
    text = Map.get(input, :label) || (Map.get(input, :opts) || [])[:label]

    if is_binary(text),
      do: Map.put(acc, to_string(name), Gettext.dgettext(gettext_module, domain, text)),
      else: acc
  end

  defp put_label(acc, _input, _gettext_module, _domain), do: acc

  defp put_sub_labels(acc, %Brando.Blueprint.Forms.Subform{sub_fields: fields}, gettext_module, domain),
    do: Enum.reduce(fields, acc, &put_label(&2, &1, gettext_module, domain))

  defp put_sub_labels(acc, _input, _gettext_module, _domain), do: acc

  defp humanize(name), do: name |> to_string() |> Phoenix.Naming.humanize()

  ## Rendering

  attr :state, :map, required: true
  attr :form_name, :string, required: true
  attr :target, :any, required: true

  @doc "The translation panel at the top of the entry form."
  def panel(%{state: %{role: :source}} = assigns) do
    ~H"""
    <section class="translation-panel is-source" aria-labelledby="translation-panel-title">
      <header>
        <h2 id="translation-panel-title">{gettext("Source of its translations")}</h2>
        <p>
          {gettext(
            "Structure, media and shared values you save here are applied to the translations below. Their translated text is kept, and changed text is marked for review."
          )}
        </p>
      </header>
      <.members state={@state} target={@target} />
    </section>
    """
  end

  def panel(%{state: %{role: :unlinked}} = assigns) do
    ~H"""
    <section
      :if={@state.can_create? and @state.missing_languages != []}
      class="translation-panel is-unlinked"
      aria-labelledby="translation-panel-title"
    >
      <header>
        <h2 id="translation-panel-title">{gettext("Translations")}</h2>
        <p>
          {gettext(
            "A translation is created as an unpublished copy of this entry, which becomes its source: structure, media and shared values follow this entry."
          )}
        </p>
      </header>
      <.create_buttons state={@state} target={@target} />
    </section>
    """
  end

  def panel(%{state: %{synchronized?: false}} = assigns) do
    ~H"""
    <section class="translation-panel is-independent" aria-labelledby="translation-panel-title">
      <header>
        <h2 id="translation-panel-title">{gettext("Independent translation")}</h2>
        <p>{gettext("This translation no longer follows a source. Its structure and shared values are edited here.")}</p>
      </header>
    </section>
    """
  end

  def panel(assigns) do
    assigns =
      assign(assigns,
        groups: Enum.group_by(assigns.state.items, & &1.kind),
        count: length(assigns.state.items)
      )

    ~H"""
    <section
      class="translation-panel is-target"
      aria-labelledby="translation-panel-title"
      id="translation-panel"
      phx-hook="Brando.TranslationWork"
      data-blocks={Jason.encode!(block_uids(@state.items))}
      data-fields={Jason.encode!(field_names(@state.items, @form_name))}
      data-locks={Jason.encode!(locks(@state, @form_name))}
    >
      <header>
        <h2 id="translation-panel-title">
          {gettext("Translation of the %{language} source", language: language_label(@state.source && @state.source.language))}
        </h2>
        <p>
          {gettext(
            "Structure, media and shared values follow the source. Edit the text here; change structure in the source."
          )}
          <.link :if={@state.source && @state.source.url} navigate={@state.source.url}>{gettext("Open the source")}</.link>
        </p>
      </header>

      <input
        :if={@state.applied_version_id}
        type="hidden"
        name="translation_review[version_id]"
        value={@state.applied_version_id}
      />

      <p :if={@state.stale?} class="translation-notice" role="status">
        {gettext("The source changed again while you were editing. Its newer changes are loaded below and are not saved yet.")}
      </p>

      <p :if={@state.structure_changed?} class="translation-structure">
        {gettext("Blocks or rows were added, removed or moved in the source. The form has the new structure.")}
      </p>

      <p :if={@count == 0 and not @state.structure_changed?} class="translation-done">
        {gettext("Nothing needs translating or reviewing.")}
      </p>

      <div :if={@count > 0} class="translation-work">
        <p class="translation-summary">
          {ngettext("%{count} item needs attention", "%{count} items need attention", @count)}
          <span :if={@state.applied_version_id}>{gettext("The changes from the source are in the form and are saved with it.")}</span>
        </p>

        <.work_group
          :if={@groups[:translate]}
          title={gettext("Needs translation")}
          items={@groups[:translate]}
          state={@state}
          acknowledge
        />
        <.work_group
          :if={@groups[:review]}
          title={gettext("Changed in the source — review the translation")}
          items={@groups[:review]}
          state={@state}
          acknowledge
        />
        <.work_group
          :if={@groups[:shared_update]}
          title={gettext("Updated from the source")}
          items={@groups[:shared_update]}
          state={@state}
        />
        <.work_group
          :if={@groups[:awaiting_translation]}
          title={gettext("Waiting for a linked translation")}
          items={@groups[:awaiting_translation]}
          state={@state}
        />
      </div>

      <.members state={@state} target={@target} />

      <div class="translation-actions">
        <button
          type="button"
          class="translation-action"
          phx-click="make_translation_independent"
          phx-target={@target}
          data-confirm={
            gettext(
              "Stop following the source? This translation keeps its content, its unsaved changes and its link to the other languages, and its structure becomes editable here. It is not published."
            )
          }
        >
          {gettext("Make independent")}
        </button>
        <button
          type="button"
          class="translation-action"
          phx-click="make_translation_source"
          phx-target={@target}
          data-confirm={
            gettext(
              "Make this translation the source? The other languages will follow its structure and shared values from its next save. Nothing is published."
            )
          }
        >
          {gettext("Make source")}
        </button>
      </div>
    </section>
    """
  end

  attr :state, :map, required: true
  attr :target, :any, required: true

  defp create_buttons(assigns) do
    ~H"""
    <div :if={@state.can_create? and @state.missing_languages != []} class="translation-create">
      <span>{gettext("Create a translation")}</span>
      <button
        :for={language <- @state.missing_languages}
        type="button"
        class="translation-action"
        phx-click="create_translation"
        phx-value-language={language.code}
        phx-target={@target}
      >
        {language.label}
      </button>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :state, :map, required: true
  attr :acknowledge, :boolean, default: false

  defp work_group(assigns) do
    ~H"""
    <div class="translation-group">
      <h3>{@title} <span>{length(@items)}</span></h3>
      <ul>
        <li :for={item <- @items}>
          <span class="translation-item-label">{item.label}</span>
          <label :if={@acknowledge} class="translation-ack">
            <input
              type="checkbox"
              name="translation_review[acknowledged][]"
              value={item.path}
              checked={item.path in @state.acknowledged}
            />
            {gettext("Reviewed")}
          </label>
        </li>
      </ul>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :target, :any, required: true

  defp members(assigns) do
    ~H"""
    <div class="translation-members">
      <h3>{gettext("Language versions")}</h3>
      <ul>
        <li :for={member <- @state.members}>
          <.link :if={member.entry_id != @state.entry_id} navigate={member.url}>{language_label(member.language)}</.link>
          <strong :if={member.entry_id == @state.entry_id}>{language_label(member.language)}</strong>
          <span :if={member.role == :source} class="translation-badge">{gettext("Source")}</span>
          <span :if={member.role == :target and not member.synchronized?} class="translation-badge">{gettext("Independent")}</span>
          <span :if={member.open > 0} class="translation-badge is-work">
            {ngettext("%{count} open item", "%{count} open items", member.open)}
          </span>
        </li>
      </ul>
      <.create_buttons state={@state} target={@target} />
    </div>
    """
  end

  defp block_uids(items), do: for(%{target: {:block, uid, _, _}} <- items, uniq: true, do: uid)

  defp field_names(items, form_name) do
    for %{target: target} <- items, uniq: true do
      case target do
        {:field, field} -> "#{form_name}[#{field}]"
        {:row, subform, _uid, _field} -> "#{form_name}[#{subform}]"
        _ -> nil
      end
    end
    |> Enum.reject(&is_nil/1)
  end

  @doc "The label of a language code, from the configured languages."
  def language_label(nil), do: ""

  def language_label(code) do
    code = to_string(code)

    case Enum.find(Brando.config(:languages) || [], &(to_string(&1[:value]) == code)) do
      nil -> String.upcase(code)
      language -> Brando.Content.Transfer.Labels.language(code, language[:text])
    end
  end

  defp admin_url(schema, id) do
    schema.__admin_route__(:update, [id])
  rescue
    _ -> nil
  end
end
