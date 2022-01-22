defmodule BrandoAdmin.Components.Form.Input.Slug do
  use BrandoAdmin, :component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase

  # prop form, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map

  # data class, :string
  # data monospace, :boolean
  # data disabled, :boolean
  # data debounce, :integer
  # data compact, :boolean
  # data slug_for, :boolean

  def render(assigns) do
    assigns = prepare_input_component(assigns)

    assigns =
      assigns
      |> assign(slug_for: assigns.opts[:for])
      |> assign_new(:url, fn -> nil end)
      |> assign_new(:data_slug_for, fn -> prepare_slug_for(assigns.form, assigns.opts[:for]) end)
      |> assign_new(:data_slug_type, fn ->
        (Keyword.get(assigns.opts, :camel_case) && "camel") || "standard"
      end)
      |> maybe_assign_url(assigns.opts[:show_url])

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= text_input @form, @field,
        class: "text monospace",
        phx_hook: "Brando.Slug",
        phx_debounce: 750,
        data_slug_for: @data_slug_for,
        data_slug_type: @data_slug_type,
        autocorrect: "off",
        spellcheck: "false" %>
      <%= if @url do %>
      <div class="badge no-case no-border">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M6.235 6.453a8 8 0 0 0 8.817 12.944c.115-.75-.137-1.47-.24-1.722-.23-.56-.988-1.517-2.253-2.844-.338-.355-.316-.628-.195-1.437l.013-.091c.082-.554.22-.882 2.085-1.178.948-.15 1.197.228 1.542.753l.116.172c.328.48.571.59.938.756.165.075.37.17.645.325.652.373.652.794.652 1.716v.105c0 .391-.038.735-.098 1.034a8.002 8.002 0 0 0-3.105-12.341c-.553.373-1.312.902-1.577 1.265-.135.185-.327 1.132-.95 1.21-.162.02-.381.006-.613-.009-.622-.04-1.472-.095-1.744.644-.173.468-.203 1.74.356 2.4.09.105.107.3.046.519-.08.287-.241.462-.292.498-.096-.056-.288-.279-.419-.43-.313-.365-.705-.82-1.211-.96-.184-.051-.386-.093-.583-.135-.549-.115-1.17-.246-1.315-.554-.106-.226-.105-.537-.105-.865 0-.417 0-.888-.204-1.345a1.276 1.276 0 0 0-.306-.43zM12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10z"/></svg> <%= @url %>
      </div>
      <% end %>
    </FieldBase.render>
    """
  end

  def maybe_assign_url(assigns, true) do
    entry = Ecto.Changeset.apply_changes(assigns.form.source)
    schema = entry.__struct__
    url = schema.__absolute_url__(entry)
    assign(assigns, :url, url)
  end

  def maybe_assign_url(assigns, _) do
    assigns
  end

  def prepare_slug_for(form, slug_for) when is_list(slug_for) do
    Enum.reduce(slug_for, [], fn sf, acc ->
      acc ++ List.wrap("#{form.id}_#{sf}")
    end)
    |> Enum.join(",")
  end

  def prepare_slug_for(form, slug_for) do
    "#{form.id}_#{slug_for}"
  end
end
