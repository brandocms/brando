defmodule BrandoAdmin.Components.Form.EntrySkeleton do
  @moduledoc """
  What the entry editor shows while an entry opens (approved October 2026).

  The form reads the entry before its first render (`Form.open_entry/1`), so
  the heading, tabs and fields are normally real from the start. What is left
  to show:

    * `blocks/1`: a heavy entry's block fields as outlines while its blocks
      load, beside its real fields, which are read-only until then. The
      toolbar says "Loading 115 blocks" (`load_state/1`) where the save state
      goes, over a 2px line (`progress/1`), and Save is disabled.
    * `form/1`: the whole form as a skeleton, when nothing of the entry is
      known yet: the layout's render on a reload or a direct link, before
      LiveView connects, and a blueprint with its own form query loading a
      heavy entry in one piece. The breadcrumb and tools are real; neutral
      bars stand where the title, status, tabs, fields and blocks go, and the
      save state reads "Opening".

  The shimmer and the line move by `transform` only, so they keep moving
  while the browser applies a large patch, and stand still under
  `prefers-reduced-motion` (`Opening.css`). The loading state is a class the
  server puts on the form root (`is-loading-blocks`), never a `:has()` above
  the block editor.
  """
  use BrandoAdmin, :component
  use BrandoAdmin.Translator
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form.EntryHeader

  # Outlines a block field shows at most: they fill a screen.
  @max_outlines 4

  @doc """
  What `form/1` shows of a blueprint's entry editor, from the schema alone:
  the breadcrumb, the section tabs' labels, which tools the toolbar has, and
  whether there are blocks.
  """
  def describe(schema, form_name \\ :default) do
    blueprint = schema.__form__(form_name)
    tabs = if blueprint, do: Enum.map(blueprint.tabs, &g(schema, &1.name)), else: []
    preview? = live_preview?(schema)
    languages? = schema.has_trait(Brando.Trait.Translatable) and schema.has_alternates?()

    drawers =
      for {trait, label} <- [
            {Brando.Trait.Meta, "Meta"},
            {Brando.Trait.Revisioned, gettext("History")},
            {Brando.Trait.ScheduledPublishing, gettext("Scheduled publishing")}
          ],
          schema.has_trait(trait),
          do: label

    %{
      crumbs: EntryHeader.crumbs(schema),
      tabs: tabs ++ drawers,
      blocks?: schema.has_trait(Brando.Trait.Blocks),
      preview?: preview?,
      more?: languages? or (preview? and BrandoAdmin.Authorization.allowed?(:export, schema))
    }
  end

  defp live_preview?(schema) do
    Code.ensure_compiled!(Brando.live_preview())
    Brando.LivePreview.has_live_preview_target(schema)
  rescue
    _ -> false
  end

  attr :id, :string, required: true
  attr :skeleton, :map, required: true, doc: "from `describe/2`"
  attr :header?, :boolean, default: true

  @doc "The whole entry editor as a skeleton: nothing of the entry is known yet."
  def form(assigns) do
    ~H"""
    <div id={@id} class="brando-form form-loading is-loading-blocks" aria-busy="true">
      <div class="form-content">
        <EntryHeader.header :if={@header?} crumbs={@skeleton.crumbs}>
          <span class="sk sk-title" aria-hidden="true"></span>
          <span class="sk-pill" aria-hidden="true"><span class="sk sk-dot"></span><span class="sk sk-text"></span></span>
        </EntryHeader.header>
        <div class="form-tabs form-tabs--split">
          <nav class="form-tab-customs pill-tabs pill-tabs--small" aria-hidden="true">
            <button
              :for={{label, index} <- Enum.with_index(@skeleton.tabs)}
              type="button"
              class={index == 0 && "active"}
              tabindex="-1"
              disabled
            >
              <span class="sk sk-tab" style={"width: #{tab_width(label)}px"}></span>
            </button>
          </nav>
          <div class="form-tab-builtins">
            <div class="page-presences" aria-hidden="true"><span class="sk sk-circle"></span></div>
            <.load_state label={gettext("Opening")} />
            <button type="button" class="form-tool-notes form-tool-icon" aria-label={gettext("Notes")} disabled>
              <.icon name="message-square" class="s" />
            </button>
            <button :if={@skeleton.preview?} type="button" class="live-preview-toggle form-tool-preview" disabled>
              <.icon name="eye" class="s" />
              <span class="tab-text">{gettext("Preview")}</span>
            </button>
            <div :if={@skeleton.more?} class="form-tool-more">
              <button type="button" class="form-tool-more-trigger form-tool-icon" aria-label={gettext("More")} disabled>
                <.icon name="ellipsis" class="s" />
              </button>
            </div>
            <div class="split-dropdown form-tool-save">
              <button type="button" class="form-tool-save-button" disabled>
                <.icon name="check" class="s" />
                <span>{gettext("Save and close")}</span>
              </button>
              <div class="split-dropdown-wrapper">
                <button type="button" class="split-dropdown-button" aria-label={gettext("Save options")} disabled>
                  <.icon name="chevron-down" class="dropdown-chevron" />
                </button>
              </div>
            </div>
          </div>
          <.progress label={gettext("Opening")} />
        </div>
        <div class="form-skeleton-fields" aria-hidden="true">
          <div :for={{label, value} <- [{38, 46}, {62, 30}, {28, 38}, {70, 52}]} class="form-skeleton-field">
            <span class="sk sk-label" style={"width: #{label}px"}></span>
            <span class="sk-input"><span class="sk sk-value" style={"width: #{value}%"}></span></span>
          </div>
        </div>
        <.blocks :if={@skeleton.blocks?} count={4} label?={false} />
      </div>
    </div>
    """
  end

  # A tab's skeleton is about as wide as its label.
  defp tab_width({:safe, label}), do: tab_width(IO.iodata_to_binary(label))
  defp tab_width(label), do: round(String.length(to_string(label)) * 6.2)

  attr :count, :integer, required: true, doc: "the field's blocks; at most #{@max_outlines} outlines are drawn"
  attr :label?, :boolean, default: true

  @doc "A block field's outlines while its blocks load."
  def blocks(assigns) do
    assigns = assign(assigns, :outlines, Enum.take(outline_shapes(), min(assigns.count, @max_outlines)))

    ~H"""
    <div class="blocks-wrapper blocks-loading" aria-hidden="true">
      <div class="label-wrapper">
        <label :if={@label?} class="control-label"><span>{gettext("Blocks")}</span></label>
        <span :if={!@label?} class="sk sk-label" style="width: 44px"></span>
      </div>
      <div :if={@outlines != []} class="blocks-content">
        <div class="sk-blocks">
          <div :for={{heading?, lines} <- @outlines} class="sk-block">
            <div class="sk-block-head"><span class="sk sk-toggle"></span><span class="sk sk-name"></span></div>
            <div class={["sk-block-body", heading? && "is-heading"]}>
              <span :for={width <- lines} class="sk sk-line" style={"width: #{width}%"}></span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # A heading, then paragraphs of a few lengths
  defp outline_shapes, do: [{true, [55]}, {false, [92, 88, 95, 60]}, {false, [70, 40]}, {false, [90, 85, 50]}]

  attr :label, :string, required: true

  @doc "The toolbar's status while the entry opens, where the save state goes."
  def load_state(assigns) do
    ~H"""
    <span class="form-load-state" role="status">{@label}</span>
    """
  end

  attr :label, :string, required: true

  @doc "The 2px line under the toolbar, moving while the entry opens."
  def progress(assigns) do
    ~H"""
    <div class="form-load-progress" role="progressbar" aria-label={@label}></div>
    """
  end

  @doc "The status text while a heavy entry's blocks load."
  def loading_blocks_label(count) do
    ngettext("Loading %{count} block", "Loading %{count} blocks", count)
  end
end
