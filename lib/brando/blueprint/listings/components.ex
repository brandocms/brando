defmodule Brando.Blueprint.Listings.Components do
  @moduledoc """
  Components to use in listings
  """
  use Phoenix.Component

  alias BrandoAdmin.Components.Content

  attr :class, :string, default: nil
  attr :padded, :boolean, default: false
  attr :image, :map, required: true
  attr :columns, :integer, required: true
  attr :size, :atom, default: :thumb
  attr :offset, :integer, default: nil

  def cover(assigns) do
    ~H"""
    <div class={[
      @class,
      @padded && "padded",
      @columns && "col-#{@columns}",
      @offset && "offset-#{@offset}"
    ]}>
      <Content.image image={@image} size={@size} />
    </div>
    """
  end

  attr :class, :string, default: nil
  attr :entry, :map, required: true
  attr :offset, :integer, default: nil

  def url(assigns) do
    assigns = assign(assigns, :status, Map.get(assigns.entry, :status))

    ~H"""
    <div class={[
      @class,
      "col-1",
      @offset && "offset-#{@offset}"
    ]}>
      <a :if={@status == :published} href={Brando.HTML.absolute_url(@entry)} target="_blank">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18">
          <path fill="none" d="M0 0h24v24H0z" /><path d="M18.364 15.536L16.95 14.12l1.414-1.414a5 5 0 1 0-7.071-7.071L9.879 7.05 8.464 5.636 9.88 4.222a7 7 0 0 1 9.9 9.9l-1.415 1.414zm-2.828 2.828l-1.415 1.414a7 7 0 0 1-9.9-9.9l1.415-1.414L7.05 9.88l-1.414 1.414a5 5 0 1 0 7.071 7.071l1.414-1.414 1.415 1.414zm-.708-10.607l1.415 1.415-7.071 7.07-1.415-1.414 7.071-7.07z" />
        </svg>
      </a>
    </div>
    """
  end

  attr :class, :string, default: nil
  attr :padded, :boolean, default: false
  attr :entry, :map, required: true
  attr :columns, :integer, required: true
  attr :offset, :integer, default: nil
  slot :default
  slot :outside

  def update_link(assigns) do
    schema = assigns.entry.__struct__

    update_url =
      Brando.routes().admin_live_path(
        Brando.endpoint(),
        schema.__modules__().admin_update_view,
        assigns.entry.id
      )

    assigns = assign(assigns, :update_url, update_url)

    ~H"""
    <div class={[
      @class,
      @columns && "col-#{@columns}",
      @offset && "offset-#{@offset}"
    ]}>
      <.link navigate={@update_url} class="entry-link">
        <%= render_slot(@inner_block) %>
      </.link>
      <%= render_slot(@outside) %>
    </div>
    """
  end
end
