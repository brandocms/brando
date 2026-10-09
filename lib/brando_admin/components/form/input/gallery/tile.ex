defmodule BrandoAdmin.Components.Form.Input.Gallery.Tile do
  @moduledoc """
  The contact-sheet grid shared by the gallery field (`Input.Gallery`) and the
  gallery block (`Blocks.GalleryBlock`).

  Each square shows the object's position, a video badge, its actions on hover
  and two status icons: the caption (images and videos) and the alt text
  (images only). Hovering an icon shows its text; clicking it opens
  `text_editor/1` under the square. Both editors render the same markup — only
  where an edit is written differs, and that stays with each editor.

  `view_switch/1` toggles the editor between this grid and its list. The choice
  is the admin's view of the gallery and is remembered in the browser; it never
  changes the saved content.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form.Input
  alias Phoenix.LiveView.JS

  @caption_extensions ~w(p bold italic link)

  attr :id, :string, required: true, doc: "DOM id of the square"
  attr :number, :integer, required: true, doc: "1-based position in the gallery"
  attr :media_type, :atom, values: [:image, :video], required: true
  attr :thumb_url, :string, default: nil
  attr :processing, :boolean, default: false
  attr :caption, :map, required: true, doc: "`%{set?: boolean, html: safe markup | nil}`"
  attr :alt, :map, default: nil, doc: "`%{set?: boolean, text: string | nil}`; images only"
  attr :editing, :atom, default: nil, values: [nil, :caption, :alt]
  attr :open_caption, :any, required: true, doc: "JS that opens the caption editor"
  attr :open_alt, :any, default: nil, doc: "JS that opens the alt text editor"
  slot :actions, doc: "Buttons shown in the top-right corner on hover"
  slot :editor, doc: "The open `text_editor/1`, rendered under the square"

  def tile(assigns) do
    ~H"""
    <div class="gallery-tile" id={@id}>
      <div class="gallery-tile-square">
        <%= cond do %>
          <% @thumb_url -> %>
            <img src={@thumb_url} alt="" loading="lazy" />
          <% @processing -> %>
            <div class="gallery-tile-placeholder">
              <svg class="spin" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
                <path fill="none" d="M0 0h24v24H0z" /><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z" />
              </svg>
            </div>
          <% true -> %>
            <div class="gallery-tile-placeholder">
              <.icon name={if @media_type == :video, do: "video", else: "image"} />
            </div>
        <% end %>

        <span class="gallery-tile-number">{@number}</span>
        <span :if={@media_type == :video} class="gallery-tile-video">▶ {gettext("Video")}</span>

        <div :if={@actions != []} class="gallery-tile-actions" data-sortable-filter>
          {render_slot(@actions)}
        </div>

        <div class="gallery-tile-meta" data-sortable-filter>
          <button
            type="button"
            class={[
              "gallery-tile-icon",
              (@caption.set? && "is-set") || "is-empty",
              @editing == :caption && "is-active"
            ]}
            aria-label={gettext("Caption")}
            aria-describedby={@caption.set? && "#{@id}-caption-peek"}
            aria-expanded={to_string(@editing == :caption)}
            phx-click={@open_caption}
          >
            <.icon name="message-square-text" />
            <span :if={@caption.set?} id={"#{@id}-caption-peek"} class="gallery-tile-peek" role="tooltip">
              <b>{gettext("Caption")}</b>
              <span class="gallery-tile-peek-text">{@caption.html}</span>
              <span class="gallery-tile-peek-hint">{gettext("Click to edit")}</span>
            </span>
          </button>
          <button
            :if={@media_type == :image && @alt}
            type="button"
            class={[
              "gallery-tile-icon",
              (@alt.set? && "is-set") || "is-missing",
              @editing == :alt && "is-active"
            ]}
            aria-label={if @alt.set?, do: gettext("Alt text"), else: gettext("No alt text")}
            aria-describedby={@alt.set? && "#{@id}-alt-peek"}
            aria-expanded={to_string(@editing == :alt)}
            phx-click={@open_alt}
          >
            <span aria-hidden="true">ALT</span>
            <span :if={@alt.set?} id={"#{@id}-alt-peek"} class="gallery-tile-peek" role="tooltip">
              <b>{gettext("Alt text")}</b>
              <span class="gallery-tile-peek-text">{@alt.text}</span>
              <span class="gallery-tile-peek-hint">{gettext("Click to edit")}</span>
            </span>
          </button>
        </div>
      </div>
      {render_slot(@editor)}
    </div>
    """
  end

  attr :id, :string, required: true
  attr :kind, :atom, values: [:caption, :alt], required: true
  attr :filename, :string, default: nil
  attr :value, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :target, :any, required: true
  attr :save_event, :string, required: true
  attr :close_event, :string, required: true
  attr :params, :map, default: %{}, doc: "Sent with the save event, alongside `value`"

  @doc """
  The popover that edits one text of one object.

  Its inputs point their `form` attribute at an id no form has, so the entry
  form around the gallery neither submits nor validates them. The
  `Brando.GalleryTextEditor` hook reads the value and pushes `save_event` to
  `target` with `params` and `value`.
  """
  def text_editor(assigns) do
    assigns =
      assigns
      |> assign(:detached_form, "#{assigns.id}-detached")
      |> assign(:form, to_form(%{"text" => assigns.value || ""}, as: "gallery_text", id: assigns.id))
      |> assign(:caption_opts, extensions: @caption_extensions)

    ~H"""
    <div
      id={@id}
      class={["gallery-text-editor", "gallery-text-editor--#{@kind}"]}
      role="dialog"
      aria-labelledby={"#{@id}-label"}
      phx-hook="Brando.GalleryTextEditor"
      data-kind={@kind}
      data-save-event={@save_event}
      data-close-event={@close_event}
      data-params={Jason.encode!(@params)}
      data-sortable-filter
    >
      <div class="gallery-text-editor-label" id={"#{@id}-label"}>
        {if @kind == :caption, do: gettext("Caption"), else: gettext("Alt text")}
        <span :if={@filename} class="gallery-text-editor-file">· {@filename}</span>
      </div>
      <%= if @kind == :caption do %>
        <Input.rich_text
          field={@form[:text]}
          label={gettext("Caption")}
          target={@target}
          input_form={@detached_form}
          opts={@caption_opts}
        />
      <% else %>
        <textarea
          id={"#{@id}-input"}
          class="gallery-text-editor-input"
          form={@detached_form}
          rows="3"
          placeholder={@placeholder}
          aria-labelledby={"#{@id}-label"}
        >{@value}</textarea>
      <% end %>
      <p class="gallery-text-editor-note">
        {gettext("Saved for this gallery only. Empty uses the image library's text.")}
      </p>
      <div class="gallery-text-editor-actions">
        <button type="button" class="secondary" data-gallery-text-cancel>{gettext("Cancel")}</button>
        <button type="button" class="primary" data-gallery-text-save>{gettext("Save")}</button>
      </div>
    </div>
    """
  end

  attr :images, :integer, required: true
  attr :missing_alt, :integer, required: true

  @doc "The icon key under the grid, with how many images lack alt text."
  def legend(assigns) do
    ~H"""
    <div class="gallery-sheet-legend">
      <span class="gallery-sheet-legend-item">
        <span class="gallery-tile-icon is-set" aria-hidden="true"><.icon name="message-square-text" /></span>
        {gettext("Caption")}
      </span>
      <span :if={@images > 0} class="gallery-sheet-legend-item">
        <span class="gallery-tile-icon is-set" aria-hidden="true">ALT</span>
        {gettext("Alt text set")}
      </span>
      <span :if={@images > 0 && @missing_alt > 0} class="gallery-sheet-legend-item is-missing">
        <span class="gallery-tile-icon is-missing" aria-hidden="true">ALT</span>
        {ngettext(
          "No alt text — %{missing} of %{count} image",
          "No alt text — %{missing} of %{count} images",
          @images,
          missing: @missing_alt
        )}
      </span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :view, :atom, values: [:grid, :list], required: true
  attr :target, :any, required: true
  attr :storage_key, :string, required: true, doc: "localStorage key for the choice"

  @doc ~S(Grid/list switch. `set_gallery_view` reaches `target` with `%{"view" => "grid" | "list"}`.)
  def view_switch(assigns) do
    ~H"""
    <div
      id={@id}
      class="gallery-view-switch"
      role="group"
      aria-label={gettext("Display")}
      phx-hook="Brando.GalleryView"
      data-view={@view}
      data-storage-key={@storage_key}
    >
      <button
        type="button"
        class={@view == :grid && "is-selected"}
        aria-pressed={to_string(@view == :grid)}
        aria-label={gettext("Grid")}
        data-tooltip={gettext("Grid")}
        data-gallery-view="grid"
        phx-click={JS.push("set_gallery_view", value: %{view: "grid"}, target: @target)}
      >
        <.icon name="layout-grid" />
      </button>
      <button
        type="button"
        class={@view == :list && "is-selected"}
        aria-pressed={to_string(@view == :list)}
        aria-label={gettext("List")}
        data-tooltip={gettext("List")}
        data-gallery-view="list"
        phx-click={JS.push("set_gallery_view", value: %{view: "list"}, target: @target)}
      >
        <.icon name="list" />
      </button>
    </div>
    """
  end

  @doc "Parses a view param; anything else is `nil`."
  def parse_view("grid"), do: :grid
  def parse_view("list"), do: :list
  def parse_view(_), do: nil

  @doc """
  The caption state for a square: a placement caption (rich text) wins over
  the record's own text (plain), which is escaped.
  """
  def caption_state(override, fallback) do
    html = Brando.Captions.safe_preview(override, fallback)
    %{set?: html != nil, html: html}
  end

  @doc "The alt text state for an image square."
  def alt_state(override, fallback) do
    text =
      Enum.find([override, fallback], &(is_binary(&1) and String.trim(&1) != ""))

    %{set?: text != nil, text: text}
  end
end
