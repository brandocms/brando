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
  alias Brando.Translations.Labels
  alias BrandoAdmin.Components.AIAction
  alias BrandoAdmin.Components.Form.Drafts
  alias BrandoAdmin.Components.Form.TranslationFill

  @doc "Assigns the translation state of the form's entry."
  def assign_state(%{assigns: %{schema: schema, entry: %{id: id} = entry}} = socket) when not is_nil(id) do
    case Translations.editor_state(schema, id) do
      nil ->
        state = if Translations.synchronized?(schema), do: unlinked(schema, entry, socket.assigns.current_user)
        assign(socket, :translation, state)

      state ->
        previous = socket.assigns[:translation]

        state = build(schema, socket.assigns.entry, state, previous, socket.assigns.current_user)

        state =
          case socket.assigns[:translation_acknowledged] do
            paths when is_list(paths) and state.acknowledged == [] -> %{state | acknowledged: paths}
            _ -> state
          end

        socket
        |> assign(:translation, state)
        |> assign(:translation_acknowledged, nil)
    end
  end

  def assign_state(socket), do: assign(socket, :translation, nil)

  # A synchronized schema's entry that has no translations yet: it becomes the
  # source when the first one is created.
  defp unlinked(schema, entry, user) do
    %{
      schema: schema,
      entry_id: entry.id,
      role: :unlinked,
      synchronized?: false,
      language: to_string(entry.language),
      source: nil,
      members: [],
      missing_languages: missing_languages(schema, entry),
      can_create?: can_create?(schema, user),
      pending: nil,
      payload: nil,
      items: [],
      structure_changed?: false,
      changes?: false,
      applied_version_id: nil,
      acknowledged: [],
      stale?: false,
      ai?: false
    }
  end

  defp build(schema, entry, state, previous, user) do
    %{member: member, source: source, pending: pending} = state
    entry_id = entry.id
    payload = pending && Translations.pending_content(pending, entry)

    %{
      schema: schema,
      entry_id: entry_id,
      role: member.role,
      synchronized?: member.synchronized,
      language: member.language,
      source: source && Map.put(source, :url, admin_url(schema, source.id)),
      members: members(schema, member.group_id),
      missing_languages: missing_languages(schema, entry),
      can_create?: can_create?(schema, user),
      pending: pending,
      payload: payload,
      items: items(schema, pending, payload, member.language),
      structure_changed?: payload != nil and structure(payload, schema) != structure(entry, schema),
      changes?: payload != nil and changes?(schema, payload, pending),
      # The version whose changes are in the form. Kept across refreshes of
      # the same entry, so a reconnecting form does not apply it twice.
      applied_version_id: previous && previous.entry_id == entry_id && previous.applied_version_id,
      acknowledged: (previous && previous.entry_id == entry_id && previous.acknowledged) || [],
      stale?: false,
      # Translate with AI (`Form.TranslationFill`), where AI is configured
      ai?: ai?(member)
    }
  end

  defp ai?(%{role: :target, synchronized: true}), do: Brando.AI.configured?()
  defp ai?(_member), do: false

  defp can_create?(schema, user) do
    Translations.duplicable?(schema) and Brando.Authorization.Boundary.authorize(user, :create, schema) == :ok
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

  # Languages without a version (`Translations.missing_languages/2`)
  defp missing_languages(schema, entry) do
    for code <- Translations.missing_languages(schema, entry), do: %{code: code, label: language_label(code)}
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
          name not in Map.get(config, :language_controlled_fields, []),
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

  # Whether applying the pending version would change the translation: a new
  # translation's first version holds only work, no changes, until the source
  # is saved again.
  # A payload stored by an earlier Brando that cannot be read is applied, as
  # before.
  defp changes?(schema, payload, pending) do
    Brando.Translations.Sync.base_fingerprint(payload, schema, Translations.module_uids([payload], schema)) !=
      pending.base_fingerprint
  rescue
    _ -> true
  end

  @doc "Whether the form should load the pending version now."
  def apply?(%{translation: %{pending: %{id: id}, applied_version_id: applied}}) when applied != id, do: true
  def apply?(_assigns), do: false

  @doc """
  Whether the pending version changes what the form holds. One that does not
  is only marked as applied (`mark_applied/1`), so its work is resolved on
  save, without loading it into the form as unsaved changes.
  """
  def changes?(%{translation: %{changes?: changes?}}), do: changes?
  def changes?(_assigns), do: false

  @doc "Marks the pending version as the one the form holds, without loading it."
  def mark_applied(%{assigns: %{translation: state}} = socket),
    do: assign(socket, :translation, %{state | applied_version_id: state.pending.id})

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

    # A block whose module no longer fits it (a leftover var or ref, a
    # retyped ref) cannot be restored from the version: it stays in the form
    # as the translation has it saved (`keep_saved`), so only the blocks the
    # version itself leaves out leave the form.
    case Brando.Drafts.Restore.prepare(draft, entry, schema, user,
           accept_conflict: true,
           compatible_only: true,
           keep_saved: true
         ) do
      {:ok, changeset, _issues} ->
        state = %{state | applied_version_id: state.pending.id}
        {:ok, changeset, assign(socket, :translation, state)}

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
      %{} = state -> assign(socket, :translation, %{state | acknowledged: paths})
      nil -> assign(socket, :translation_acknowledged, paths)
    end
  end

  def put_acknowledged(socket, _params), do: socket

  @doc "What the save reports to `Brando.Translations.target_saved/3`."
  def review(%{translation: %{} = state} = assigns),
    do: %{version_id: version_id(assigns), acknowledged: state.acknowledged}

  def review(_assigns), do: nil

  ## Work items

  defp items(_schema, nil, _payload, _language), do: []

  defp items(schema, pending, payload, language) do
    labels = Labels.field_labels(schema)
    blocks = Labels.block_index(schema, payload)

    open = Enum.filter(pending.work_items, &is_nil(&1.resolved_at))
    titles = linked_titles(open, blocks)

    open
    |> Enum.sort_by(&{kind_order(&1.kind), &1.path})
    |> Enum.map(fn item ->
      target = Labels.target(item.path, blocks)
      entries = linked_entries(item, target, blocks, titles, to_string(language))
      linked = if entries == [], do: nil, else: Enum.map_join(entries, ", ", & &1.title)
      base = Labels.label(target, labels)

      %{
        path: item.path,
        kind: item.kind,
        label: with_linked(base, linked),
        base_label: if(linked, do: String.replace_suffix(base, " › " <> gettext("media"), ""), else: base),
        entries: entries,
        linked: linked,
        target: target
      }
    end)
  end

  # A link's item names the entry it points at: the one it now follows for an
  # update, the one still waiting for a translation otherwise. A selection
  # moved onto this language names the entries it now links to in it.
  defp linked_entries(item, target, blocks, titles, language) do
    item
    |> linked_ids(target, blocks)
    |> Enum.filter(fn id -> item.kind != :relinked or match?(%{language: ^language}, titles[id]) end)
    |> Enum.map(fn id ->
      case titles[id] do
        %{title: title, url: url} -> %{title: title, url: url}
        nil -> %{title: "##{id}", url: nil}
      end
    end)
  end

  defp with_linked(label, nil), do: label
  defp with_linked(label, linked), do: "#{String.replace_suffix(label, " › " <> gettext("media"), "")} → #{linked}"

  defp linked_ids(%{kind: :awaiting_translation, path: path}, _target, _blocks) do
    case Regex.run(~r{/identifiers?/(\d+)$}, path) do
      [_, id] -> [String.to_integer(id)]
      _ -> []
    end
  end

  defp linked_ids(%{kind: kind}, {:block, uid, _module, ["vars", key, "media"]}, blocks)
       when kind in [:shared_update, :relinked] do
    blocks
    |> Enum.find_value(fn {_identity, block} ->
      block.uid == uid && Enum.find_value(block.vars, &(&1.key == key && &1.identifier_id))
    end)
    |> List.wrap()
  end

  defp linked_ids(%{kind: :relinked}, {:block, uid, _module, ["identifiers"]}, blocks) do
    Enum.find_value(blocks, [], fn {_identity, block} -> block.uid == uid && block.identifier_ids end)
  end

  defp linked_ids(_item, _target, _blocks), do: []

  defp linked_titles(items, blocks) do
    ids = items |> Enum.flat_map(&linked_ids(&1, Labels.target(&1.path, blocks), blocks)) |> Enum.uniq()

    if ids == [] do
      %{}
    else
      import Ecto.Query

      from(i in Brando.Content.Identifier, where: i.id in ^ids)
      |> Brando.Repo.all()
      |> Map.new(fn i ->
        {i.id,
         %{
           title: Brando.Content.Identifier.title_text(i),
           language: i.language && to_string(i.language),
           url: admin_url(i.schema, i.entry_id)
         }}
      end)
    end
  end

  defp kind_order(:translate), do: 0
  defp kind_order(:review), do: 1
  defp kind_order(:shared_update), do: 2
  defp kind_order(:relinked), do: 3
  defp kind_order(:awaiting_translation), do: 4

  ## Rendering

  attr :state, :map, required: true
  attr :form_name, :string, required: true
  attr :target, :any, required: true
  attr :fill, :map, default: nil, doc: "Translate with AI's run (`Form.TranslationFill`)"
  attr :editing, :boolean, default: true, doc: "whether this tab edits the entry"
  attr :actionable, :any, default: MapSet.new(), doc: "the items with an AI action (`TranslationFill.actionable/1`)"

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
    groups = Enum.group_by(assigns.state.items, & &1.kind)

    assigns =
      assign(assigns,
        groups: groups,
        count: length(assigns.state.items),
        ai?: assigns.state.ai? and (Map.has_key?(groups, :translate) or Map.has_key?(groups, :review))
      )

    ~H"""
    <section
      class="translation-panel is-target"
      aria-labelledby="translation-panel-title"
      id="translation-panel"
      phx-hook="Brando.TranslationWork"
      data-blocks={Jason.encode!(block_uids(@state.items))}
      data-notes={Jason.encode!(block_notes(@state))}
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
          <span :if={@state.applied_version_id && @state.changes?}>
            {gettext("The changes from the source are in the form and are saved with it.")}
          </span>
        </p>

        <.ai_fill
          :if={@ai?}
          fill={@fill}
          target={@target}
          editing={@editing}
        />

        <.work_group
          :if={@groups[:translate]}
          title={gettext("Needs translation")}
          items={@groups[:translate]}
          state={@state}
          fill={@fill}
          ai={@ai?}
          actionable={@actionable}
          editing={@editing}
          target={@target}
          acknowledge
        />
        <.work_group
          :if={@groups[:review]}
          title={gettext("Changed in the source — review the translation")}
          items={@groups[:review]}
          state={@state}
          fill={@fill}
          ai={@ai?}
          actionable={@actionable}
          editing={@editing}
          target={@target}
          acknowledge
        />
        <.work_group
          :if={@groups[:shared_update]}
          title={gettext("Updated from the source")}
          description={
            gettext("The source changed these. The new values are already in the form, so saving is all they need.")
          }
          items={@groups[:shared_update]}
          state={@state}
        />
        <.work_group
          :if={@groups[:relinked]}
          title={gettext("Repointed automatically")}
          description={relinked_description(@state)}
          items={@groups[:relinked]}
          state={@state}
        />
        <.work_group
          :if={@groups[:awaiting_translation]}
          title={gettext("Waiting for a linked translation")}
          description={awaiting_description(@state)}
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

  attr :fill, :map, required: true
  attr :target, :any, required: true
  attr :editing, :boolean, required: true

  # Translate with AI over every open text, and how the run went
  defp ai_fill(assigns) do
    assigns =
      assign(assigns,
        running?: TranslationFill.running?(assigns.fill),
        status: assigns.fill && assigns.fill.status
      )

    ~H"""
    <div class="translation-ai">
      <AIAction.button
        data-testid="translation-ai-all"
        phx-click="translate_with_ai"
        phx-target={@target}
        busy={@running?}
        disabled={@running? or not @editing}
      >
        {gettext("Translate with AI")}
      </AIAction.button>
      <p :if={@status == :running} class="translation-ai-status" data-ai-status="running" role="status">
        {ai_running_text(@fill)}
        <progress
          :if={elem(@fill.progress, 1) > 1}
          max={elem(@fill.progress, 1)}
          value={elem(@fill.progress, 0)}
          aria-label={gettext("Translating with AI")}
        />
      </p>
      <p :if={@status == :done} class="translation-ai-status" data-ai-status="done" role="status">
        {ai_done_text(@fill)}
      </p>
      <p :if={@status == :failed} class="translation-ai-status is-error" data-ai-status="failed" role="alert">
        {gettext("Translating with AI failed. Nothing was changed; try again.")}
      </p>
      <p :if={@status == :dropped} class="translation-ai-status is-error" data-ai-status="dropped" role="alert">
        {gettext("The source changed while AI was translating, so nothing was filled in. Save, then try again.")}
      </p>
    </div>
    """
  end

  defp ai_running_text(fill) do
    ngettext("Translating %{count} text with AI…", "Translating %{count} texts with AI…", length(fill.keys))
  end

  defp ai_done_text(fill) do
    %{filled: filled, not_filled: not_filled} = TranslationFill.counts(fill)
    done = ngettext("AI filled in %{count} text.", "AI filled in %{count} texts.", filled)

    rest =
      if not_filled > 0,
        do:
          " " <>
            ngettext(
              "%{count} was not filled in; see why below.",
              "%{count} were not filled in; see why below.",
              not_filled
            ),
        else: ""

    done <> rest <> " " <> gettext("Check the texts, then save.")
  end

  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :items, :list, required: true
  attr :state, :map, required: true
  attr :acknowledge, :boolean, default: false
  attr :fill, :map, default: nil
  attr :ai, :boolean, default: false
  attr :actionable, :any, default: MapSet.new()
  attr :editing, :boolean, default: true
  attr :target, :any, default: nil

  defp work_group(assigns) do
    assigns = assign(assigns, :running?, TranslationFill.running?(assigns.fill))

    ~H"""
    <div class="translation-group">
      <h3>{@title} <span>{length(@items)}</span></h3>
      <p :if={@description} class="translation-group-description">{@description}</p>
      <ul>
        <li
          :for={item <- @items}
          data-translation-item={item.path}
          data-ai={ai_mark_value(ai_mark(@fill, item.path))}
        >
          <span :if={item.entries == []} class="translation-item-label">{item.label}</span>
          <span :if={item.entries != []} class="translation-item-label">
            {item.base_label} →
            <%= for {entry, index} <- Enum.with_index(item.entries) do %>
              <%= if index > 0 do %>
                ,
              <% end %>
              <.link
                :if={entry.url}
                href={entry.url}
                target="_blank"
                title={gettext("Edit in a new tab")}
              >{entry.title}</.link><span :if={!entry.url}>{entry.title}</span>
            <% end %>
          </span>
          <span :if={@ai or @acknowledge} class="translation-item-actions">
            <.ai_mark mark={ai_mark(@fill, item.path)} />
            <AIAction.button
              :if={@ai and item.path in @actionable}
              size={:icon}
              data-testid="translation-ai-item"
              phx-click="translate_with_ai"
              phx-value-key={item.path}
              phx-target={@target}
              busy={@running? and item.path in @fill.keys}
              disabled={@running? or not @editing}
              aria-label={gettext("Translate %{label} with AI", label: item.label)}
              data-tooltip={gettext("Translate with AI")}
            />
            <label :if={@acknowledge} class="translation-ack">
              <input
                type="checkbox"
                name="translation_review[acknowledged][]"
                value={item.path}
                checked={item.path in @state.acknowledged}
              />
              {gettext("Reviewed")}
            </label>
          </span>
        </li>
      </ul>
    </div>
    """
  end

  defp ai_mark(%{marks: marks}, path), do: Map.get(marks, path)
  defp ai_mark(_fill, _path), do: nil

  defp ai_mark_value({:skipped, _code}), do: "skipped"
  defp ai_mark_value(mark) when is_atom(mark) and not is_nil(mark), do: to_string(mark)
  defp ai_mark_value(_mark), do: nil

  attr :mark, :any, required: true

  # What Translate with AI did with an item: filled it in, kept the
  # editor's text, or left it with the reason
  defp ai_mark(%{mark: :filled} = assigns) do
    ~H"""
    <span class="badge badge--ai">{gettext("Filled in by AI")}</span>
    """
  end

  defp ai_mark(%{mark: :kept} = assigns) do
    ~H"""
    <span class="translation-ai-reason" data-ai-reason>{gettext("Changed during the run: your text was kept")}</span>
    """
  end

  defp ai_mark(%{mark: {:skipped, code}} = assigns) do
    assigns = assign(assigns, :reason, skipped_reason(code))

    ~H"""
    <span class="translation-ai-reason is-error" data-ai-reason>{@reason}</span>
    """
  end

  defp ai_mark(assigns), do: ~H""

  defp skipped_reason("html_changed"), do: gettext("Not filled in: AI lost the formatting or links")
  defp skipped_reason("placeholders_changed"), do: gettext("Not filled in: AI changed the template placeholders")
  defp skipped_reason(_code), do: gettext("Not filled in: AI returned no text")

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
          <span :if={member.role == :source} class="badge">{gettext("Source")}</span>
          <span :if={member.role == :target and not member.synchronized?} class="badge">{gettext("Independent")}</span>
          <span :if={member.open > 0} class="badge badge--attention">
            {ngettext("%{count} open item", "%{count} open items", member.open)}
          </span>
        </li>
      </ul>
      <.create_buttons state={@state} target={@target} />
    </div>
    """
  end

  defp block_uids(items), do: for(%{target: {:block, uid, _, _}} <- items, uniq: true, do: uid)

  defp relinked_description(state) do
    gettext(
      "The source links to pages in %{source} that also exist in %{language}. Here, they link to the %{language} versions instead. You don't need to do anything but save.",
      language: language_word(state.language),
      source: language_word(state.source && state.source.language)
    )
  end

  defp awaiting_description(state) do
    gettext(
      "The source links to entries that have no %{language} version yet. Until they do, this translation links to the %{source} ones. Once they are translated, the links move over by themselves.",
      language: language_word(state.language),
      source: language_word(state.source && state.source.language)
    )
  end

  # What a marked block shows about its waiting links, by block uid: the block
  # itself gives no hint why its selection looks as it does.
  defp block_notes(state) do
    state.items
    |> Enum.filter(&match?(%{kind: :awaiting_translation, target: {:block, _, _, _}}, &1))
    |> Enum.group_by(fn %{target: {:block, uid, _, _}} -> uid end, & &1.linked)
    |> Map.new(fn {uid, titles} ->
      titles = titles |> Enum.reject(&is_nil/1) |> Enum.uniq()

      {uid,
       ngettext(
         "Waiting for a %{language} version of %{entries}. Until then, this block links to the %{source} one. Once it is translated, the link moves over by itself.",
         "Waiting for %{language} versions of %{entries}. Until then, this block links to the %{source} ones. Once they are translated, the links move over by themselves.",
         length(titles),
         language: language_word(state.language),
         source: language_word(state.source && state.source.language),
         entries: Enum.join(titles, ", ")
       )}
    end)
  end

  # A language's name inside a sentence: Norwegian writes it in lower case,
  # English does not.
  defp language_word(code) do
    label = language_label(code)
    if Gettext.get_locale(Brando.Gettext) == "en", do: label, else: String.downcase(label)
  end

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
