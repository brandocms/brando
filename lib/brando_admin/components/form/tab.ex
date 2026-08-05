defmodule BrandoAdmin.Components.Form.Tab do
  @moduledoc false
  use BrandoAdmin, :component
  alias Phoenix.LiveView.JS

  attr :active_tab, :string, required: true
  slot :buttons, required: true
  slot :tabs, required: true

  def tabs(assigns) do
    ~H"""
    <div class="tab-container">
      <div class="tab-header">
        {render_slot(@buttons)}
      </div>
      <div class="tab-content">
        {render_slot(@tabs)}
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :active_tab, :string, required: true
  attr :target, :any, required: true

  def tab_button(assigns) do
    ~H"""
    <button
      type="button"
      class={["tab-button", @active_tab == @id && "active"]}
      phx-click={JS.push("select_tab", value: %{tab: @id}, target: @target)}
    >
      {@label}
    </button>
    """
  end

  attr :id, :string, required: true
  attr :active_tab, :string, required: true
  slot :inner_block, required: true

  # The `:if` here is LOAD-BEARING — do not "fix" it into a CSS toggle without
  # reworking the video drawer first. It renders that drawer's Upload and
  # External-URL sub-tabs, and the two panels bind the SAME field: the upload
  # panel carries a hidden `video[type]` of `:upload`, while the external panel
  # binds `video[type]` to a Vimeo/YouTube select (`form.ex`, the two
  # `Tab.tab_content` calls). Mounting both was tried and broke
  # `e2e tests/projects/projects.spec.js:290` — an uploaded video no longer
  # produced an "Edit video" button. Wrapping the inactive panel in a
  # `<fieldset disabled>` to keep it out of form submission did NOT fix it
  # either, so the duplicate-name serialization is at most part of the story.
  #
  # The cost of keeping it is real but narrow: switching sub-tabs mid-edit drops
  # an unflushed `source_url`, because the input is unmounted and there is
  # nothing left for LiveView recovery to replay (F in the form-audit plan).
  # Fixing that properly means the drawer modelling upload-vs-external as one
  # `type` decision instead of two widgets for one field.
  def tab_content(assigns) do
    ~H"""
    <div :if={@active_tab == @id} class="tab-panel" id={"tab-panel-#{@id}"}>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
