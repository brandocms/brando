defmodule BrandoAdmin.Components.Form.VarLayout do
  @moduledoc """
  Composes the editor layout of a module's variables.

  The canvas is a live rendering of what `Brando.Content.Var.Layout` will
  derive: rows packed out of `sequence` + `new_row`, with each var claiming
  `width` units of twelve. Beside it sits a preview built from the very
  components the block editor uses, so layout stops being authored blind.

  ## Division of labour

  Dragging is the browser's job — the `Brando.VarLayout` hook owns SortableJS
  and, on every drop, pushes the *structure* it can see:

      %{"rows" => [["heading"], ["cta_text", "show_arrow"]], "surface" => "content"}

  Everything derived from that structure — `sequence`, `new_row`, `placement` —
  is computed server-side by `Layout.flatten/1`. The hook never tracks a
  sequence number, so a dropped frame or a mid-drag patch cannot desynchronise
  the model.

  Width, placement and visibility are plain `phx-click` events: they are
  discrete, cheap, and benefit from the server rejecting an impossible change
  (a `1/1` dropped into a row with four units free) with a real message.
  """

  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Content.Var
  alias Brando.Content.Var.Layout
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias Ecto.Changeset

  @surfaces [:content, :config]

  def mount(socket) do
    {:ok,
     socket
     |> assign(:surface, :content)
     |> assign_new(:form_key, fn -> "default" end)
     |> assign_new(:surfaces, fn -> @surfaces end)
     |> assign_new(:width_choices, fn -> width_choices() end)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_layout()}
  end

  defp assign_layout(socket) do
    entries = entries(socket.assigns.form)
    surface = socket.assigns.surface

    socket
    |> assign(:rows, entries |> Enum.filter(&(&1.placement == surface)) |> pack())
    |> assign(:hidden_vars, Enum.filter(entries, &(&1.placement == :hidden)))
    |> assign(:unplaced, Enum.count(entries, &blank?(&1.key)))
  end

  defp pack(entries) do
    entries
    |> Enum.sort_by(& &1.sequence)
    |> Layout.pack()
  end

  # One pass over the vars produces everything the canvas needs: the layout
  # facts it packs with, and the sub-form each chip acts on. The sub-forms are
  # built exactly as `<.inputs_for>` builds them, so `index` matches the ids of
  # the edit modals rendered next to us — that is what lets a chip open one.
  defp entries(form) do
    form.source
    |> then(&form.impl.to_form(&1, form, :vars, []))
    |> Enum.reject(&(&1.source.action in [:replace, :delete]))
    |> Enum.map(fn var_form ->
      %{
        form: var_form,
        index: var_form.index,
        key: Changeset.get_field(var_form.source, :key),
        label: Changeset.get_field(var_form.source, :label),
        type: Changeset.get_field(var_form.source, :type),
        width: Changeset.get_field(var_form.source, :width) || :full,
        new_row: Changeset.get_field(var_form.source, :new_row) == true,
        placement: Changeset.get_field(var_form.source, :placement) || :content,
        sequence: Changeset.get_field(var_form.source, :sequence) || 0
      }
    end)
  end

  # A var with no key cannot be addressed by the canvas — it is mid-creation and
  # will appear as soon as it is named.
  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  defp width_choices do
    Enum.map(Layout.widths(), fn width ->
      %{value: width, label: width_label(width), hint: width_hint(width)}
    end)
  end

  defp width_label(:full), do: "1/1"
  defp width_label(:half), do: "1/2"
  defp width_label(:third), do: "1/3"
  defp width_label(:fourth), do: "1/4"
  defp width_label(width), do: to_string(width)

  defp width_hint(:full), do: gettext("Full row")
  defp width_hint(:half), do: gettext("Half a row — 6 of 12 units")
  defp width_hint(:third), do: gettext("A third — 4 of 12 units")
  defp width_hint(:fourth), do: gettext("A quarter — 3 of 12 units")
  defp width_hint(:auto), do: gettext("As wide as its content")
  defp width_hint(:fill), do: gettext("Takes the units left over")

  # -- render ---------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <div class="var-layout var-layout-split" id={@id}>
      <section class="var-layout-panel">
        <div class="var-layout-panel-head">
          <div>
            <h2>{gettext("Editor layout")}</h2>
            <p class="var-layout-sub">
              {gettext("Drag variables between rows, or drag a row by its handle to reorder.")}
              {gettext("Each row holds 12 units, up to 4 variables.")}
            </p>
          </div>
          <div class="var-layout-surfaces" role="tablist">
            <button
              :for={surface <- @surfaces}
              type="button"
              role="tab"
              class={@surface == surface && "active"}
              aria-selected={to_string(@surface == surface)}
              phx-click={JS.push("select_surface", target: @myself)}
              phx-value-surface={surface}
            >
              {surface_label(surface)}
            </button>
          </div>
        </div>

        <div class="var-layout-panel-body">
          <div class="var-layout-ruler" aria-hidden="true">
            <span :for={unit <- 1..Layout.row_units()}>{unit}</span>
          </div>

          <%!-- One hook owns every Sortable in here: the per-row chip lists, the
                row list itself, and the trailing new-row zone. LiveView still owns
                the DOM — the hook rebuilds its Sortables on each patch rather than
                freezing the subtree with phx-update="ignore", which would stop
                width and placement changes from ever rendering. --%>
          <div
            id={"#{@id}-rows"}
            class="var-layout-rows"
            phx-hook="Brando.VarLayout"
            data-target={@myself}
            data-surface={@surface}
          >
            <div class="var-layout-rows-inner">
              <.rows
                rows={@rows}
                surface={@surface}
                width_choices={@width_choices}
                target={@myself}
                form={@form}
                form_key={@form_key}
              />
            </div>

            <div class="var-layout-new-row" data-var-layout-new-row>
              <span>{gettext("Drop here to start a new row")}</span>
            </div>
          </div>

          <div class="var-layout-foot">
            <button
              type="button"
              class="module-add-button"
              phx-click={show_modal("##{@form.id}-#{@form_key}-create-var")}
            >
              <.icon name="hero-plus" />
              {gettext("Add variable")}
            </button>
            <span :if={@unplaced > 0} class="var-layout-note">
              {ngettext(
                "1 variable has no key yet and cannot be placed.",
                "%{count} variables have no key yet and cannot be placed.",
                @unplaced
              )}
            </span>
          </div>

          <section class="var-layout-tray">
            <div class="var-layout-tray-head">
              <h3>{gettext("Hidden from editors")}</h3>
              <p>{gettext("Template-only constants. Still available in the template.")}</p>
            </div>
            <div class="var-layout-tray-items">
              <span :if={@hidden_vars == []} class="empty">{gettext("Nothing hidden.")}</span>
              <div :for={entry <- @hidden_vars} class="var-tray-chip">
                <span>{entry.key}</span>
                <button type="button" phx-click={JS.push("show_var", target: @myself)} phx-value-key={entry.key}>
                  {gettext("Show")}
                </button>
              </div>
            </div>
          </section>
        </div>
      </section>

      <section class="var-layout-panel">
        <div class="var-layout-panel-head">
          <div>
            <h2>{gettext("What the editor sees")}</h2>
            <p class="var-layout-sub">{gettext("Live, from the layout beside it.")}</p>
          </div>
        </div>

        <%!-- Deliberately the block editor's own markup — `.block`, `.block-vars`,
              `.block-vars-row` — so Block.css styles this exactly as it styles the
              real thing. A preview with its own stylesheet would drift from what it
              claims to show, which is the one thing it must not do. --%>
        <div class="var-layout-preview-scroll">
          <article class="block var-preview-block">
            <div class="block-toolbar">
              <span class="var-preview-switch" aria-hidden="true"><i></i></span>
              <span class="var-preview-type">{surface_label(@surface)}</span>
            </div>

            <div class="block-vars-wrapper">
              <div class="vars-info">
                <div class="icon"><span class="hero-variable-mini"></span></div>
                <div class="info">
                  <span class="vars-label">{gettext("Block")}<br />{gettext("Variables")}</span>
                </div>
              </div>

              <%!-- Disabled so the preview's inputs are never submitted: the real
                    fields live in the edit modals beside this component, and two
                    live copies of one field would fight over the same params. --%>
              <fieldset class="block-vars" disabled>
                <div :if={@rows == []} class="preview-empty">
                  {gettext("No variables on this surface yet.")}
                </div>
                <div :for={row <- @rows} class="block-vars-row">
                  <.live_component
                    :for={entry <- row}
                    module={RenderVar}
                    id={"#{@id}-preview-#{@surface}-#{entry.key}"}
                    var={preview_form(entry.form)}
                    render={:all}
                  />
                </div>
              </fieldset>
            </div>

            <div class="var-preview-stub">
              <span>{gettext("Template output renders here")}</span>
            </div>
          </article>
        </div>
      </section>
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :surface, :atom, required: true
  attr :width_choices, :list, required: true
  attr :target, :any, required: true
  attr :form, :any, required: true
  attr :form_key, :string, required: true

  defp rows(assigns) do
    ~H"""
    <div :for={{row, index} <- Enum.with_index(@rows)} class="var-layout-row" data-row={index}>
      <div class="var-layout-gutter">
        <button
          type="button"
          class="var-row-handle"
          title={gettext("Drag to reorder this row")}
          aria-label={gettext("Reorder row %{number}", number: index + 1)}
        >
          <.icon name="hero-bars-2" />
        </button>
        <span class="var-row-meter" title={row_meter_title(row)}>
          <b class={Layout.free_units(row) == 0 && "full"}>{Layout.used_units(row)}</b>
          <i class="rule"></i>
          <span>{Layout.row_units()}</span>
          <span :if={Enum.any?(row, &Layout.flex?(&1.width))} class="flex-mark">
            <.icon name="hero-arrows-right-left" />
          </span>
        </span>
      </div>

      <div class="var-layout-slots" data-row={index}>
        <.chip
          :for={entry <- row}
          entry={entry}
          surface={@surface}
          width_choices={@width_choices}
          target={@target}
          form={@form}
          form_key={@form_key}
        />
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :surface, :atom, required: true
  attr :width_choices, :list, required: true
  attr :target, :any, required: true
  attr :form, :any, required: true
  attr :form_key, :string, required: true

  defp chip(assigns) do
    ~H"""
    <div class="var-chip" data-key={@entry.key} data-width={@entry.width}>
      <div class="var-chip-top">
        <span class="var-chip-key" title={@entry.key}>{@entry.key}</span>
        <span class="var-chip-type">{@entry.type}</span>
      </div>

      <%!-- The chip is the variable list now, so its body opens the same edit
            modal the list used to. The modal itself is rendered by ModuleProps,
            which owns the `<.inputs_for>` these ids come from. --%>
      <button
        type="button"
        class="var-chip-label"
        phx-click={show_modal("##{@form.id}-#{@form_key}-var-#{@entry.index}")}
        aria-label={gettext("Edit variable %{key}", key: @entry.key)}
      >
        {@entry.label}
      </button>

      <%!-- Widths and actions share one footer toolbar. They used to be two
            stacked rows, which read as a stray strip of icons under the label;
            side by side they scan as one control bar and save a row. On a
            quarter-width chip there is not room for both, so the group wraps. --%>
      <div class="var-chip-footer">
        <div class="var-chip-widths">
          <div class="var-width-group">
            <button
              :for={choice <- @width_choices}
              :if={choice.value in [:full, :half, :third, :fourth]}
              type="button"
              class={choice.value == @entry.width && "on"}
              title={choice.hint}
              phx-click={JS.push("set_var_width", target: @target)}
              phx-value-key={@entry.key}
              phx-value-width={choice.value}
            >
              {choice.label}
            </button>
          </div>
          <div class="var-width-group">
            <button
              :for={choice <- @width_choices}
              :if={choice.value in [:auto, :fill]}
              type="button"
              class={choice.value == @entry.width && "on"}
              title={choice.hint}
              phx-click={JS.push("set_var_width", target: @target)}
              phx-value-key={@entry.key}
              phx-value-width={choice.value}
            >
              {choice.label}
            </button>
          </div>
        </div>

        <div class="var-chip-actions">
          <button
            type="button"
            title={move_hint(@surface)}
            aria-label={move_hint(@surface)}
            phx-click={JS.push("move_var", target: @target)}
            phx-value-key={@entry.key}
          >
            <.icon name={(@surface == :content && "hero-arrow-right") || "hero-arrow-left"} />
          </button>
          <button
            type="button"
            title={gettext("Hide from editors — template only")}
            aria-label={gettext("Hide from editors — template only")}
            phx-click={JS.push("hide_var", target: @target)}
            phx-value-key={@entry.key}
          >
            <.icon name="hero-eye-slash" />
          </button>
          <button
            type="button"
            title={gettext("Duplicate")}
            aria-label={gettext("Duplicate variable %{key}", key: @entry.key)}
            phx-click={JS.push("duplicate_var")}
            phx-value-index={@entry.index}
          >
            <.icon name="hero-document-duplicate" />
          </button>
          <%!-- Ecto's `drop_param`: the button's own name/value is what removes the
              var, so this has to be a submit-time param rather than an event. --%>
          <button
            type="button"
            class="var-chip-danger"
            title={gettext("Delete")}
            aria-label={gettext("Delete variable %{key}", key: @entry.key)}
            phx-click={JS.dispatch("change")}
            phx-confirm={gettext("Delete variable %{key}?", key: @entry.key)}
            name={"#{@form.name}[drop_var_ids][]"}
            value={@entry.index}
          >
            <.icon name="hero-x-mark" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp surface_label(:content), do: gettext("In the block")
  defp surface_label(:config), do: gettext("Configure modal")

  defp move_hint(:content), do: gettext("Move to the Configure modal")
  defp move_hint(:config), do: gettext("Move into the block")

  defp row_meter_title(row) do
    gettext("%{used} of %{total} units used",
      used: Layout.used_units(row),
      total: Layout.row_units()
    )
  end

  # The preview reuses the live var form so it renders exactly what the block
  # editor will. The form `id` is namespaced because `RenderVar` derives the ids
  # of its nested live components from it, and the edit modals beside us already
  # render a set with the unprefixed ids — two components cannot share one.
  # `name` is deliberately left alone: the preview is inside a disabled
  # fieldset, so its inputs never reach the params.
  defp preview_form(var_form), do: %{var_form | id: "varlayout-preview-#{var_form.id}"}

  # -- events ---------------------------------------------------------------

  def handle_event("select_surface", %{"surface" => surface}, socket) do
    {:noreply,
     socket
     |> assign(:surface, to_surface(surface))
     |> assign_layout()}
  end

  @doc """
  Applies a drop reported by the JS hook.

  The payload only describes which key sits in which row; every stored field is
  derived from it here.
  """
  def handle_event("reposition_vars", %{"rows" => rows, "surface" => surface}, socket) do
    layout =
      socket.assigns.form
      |> entries()
      |> Layout.merge_surface(to_surface(surface), sanitize_rows(rows))

    {:noreply, apply_layout(socket, layout)}
  end

  def handle_event("set_var_width", %{"key" => key, "width" => width}, socket) do
    width = to_width(width)

    case room_for_width(socket, key, width) do
      :ok ->
        {:noreply, update_var(socket, key, %{width: width})}

      {:error, free} ->
        {:noreply,
         send_toast(
           socket,
           gettext(
             "%{label} needs %{needed} units — only %{free} free in that row. Narrow another variable, or start a new row.",
             label: width_label(width),
             needed: Layout.unit_cost(width),
             free: free
           )
         )}
    end
  end

  def handle_event("move_var", %{"key" => key}, socket) do
    target = if socket.assigns.surface == :content, do: :config, else: :content

    {:noreply,
     socket
     |> update_var(key, %{placement: target, new_row: true})
     |> send_toast(gettext("%{key} moved to %{surface}.", key: key, surface: surface_label(target)))}
  end

  def handle_event("hide_var", %{"key" => key}, socket) do
    {:noreply,
     socket
     |> update_var(key, %{placement: :hidden, new_row: true})
     |> send_toast(gettext("%{key} is now template-only.", key: key))}
  end

  def handle_event("show_var", %{"key" => key}, socket) do
    {:noreply, update_var(socket, key, %{placement: socket.assigns.surface, new_row: true})}
  end

  # -- changeset plumbing ---------------------------------------------------

  # Rows arrive as raw JSON; anything that is not a string cannot be a var key.
  # Unknown-but-string keys are filtered later by `Layout.merge_surface/3`.
  defp sanitize_rows(rows) do
    rows
    |> Enum.map(fn row -> Enum.filter(row, &is_binary/1) end)
    |> Enum.reject(&(&1 == []))
  end

  defp room_for_width(socket, key, width) do
    row =
      socket.assigns.rows
      |> Enum.find([], fn row -> Enum.any?(row, &(&1.key == key)) end)
      |> Enum.reject(&(&1.key == key))

    if Layout.used_units(row) + Layout.unit_cost(width) <= Layout.row_units() do
      :ok
    else
      {:error, Layout.free_units(row)}
    end
  end

  defp update_var(socket, key, attrs) do
    apply_vars(socket, fn vars ->
      Enum.map(vars, fn var ->
        if Changeset.get_field(var, :key) == key, do: Changeset.change(var, attrs), else: var
      end)
    end)
  end

  defp apply_layout(socket, layout_attrs) do
    apply_vars(socket, fn vars ->
      vars
      |> Enum.map(fn var ->
        case Map.get(layout_attrs, Changeset.get_field(var, :key)) do
          nil -> var
          attrs -> Changeset.change(var, attrs)
        end
      end)
      # The association's *order* is what survives a save, not the `sequence` we
      # just wrote: `<.inputs_for>` renders `sort_var_ids` in list order and
      # Ecto's `sort_param` rewrites `sequence` from that on submit. Reorder the
      # list to agree with the layout, or the drop is undone on save.
      |> Enum.sort_by(&(Changeset.get_field(&1, :sequence) || 0))
    end)
  end

  # The parent LiveView owns the module changeset, so hand the new one back and
  # let it re-render us. The local assign is only so this render cycle already
  # shows the change instead of flashing the previous layout for one frame.
  defp apply_vars(socket, fun) do
    changeset = socket.assigns.form.source

    updated =
      changeset
      |> Changeset.get_assoc(:vars)
      |> fun.()

    updated_changeset = Changeset.put_assoc(changeset, :vars, updated)

    send(self(), {:var_layout_changeset, updated_changeset})

    socket
    |> assign(:form, to_form(updated_changeset, []))
    |> assign_layout()
  end

  defp send_toast(socket, message) do
    send(self(), {:toast, message})
    socket
  end

  defp to_surface("config"), do: :config
  defp to_surface(_), do: :content

  defp to_width(width) do
    Enum.find(Layout.widths(), :full, &(to_string(&1) == width))
  end

  @doc false
  def surfaces, do: @surfaces

  @doc false
  def default_width_for(%Var{type: type}), do: Layout.default_width(type)
end
