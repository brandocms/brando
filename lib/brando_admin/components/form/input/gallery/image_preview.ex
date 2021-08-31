defmodule BrandoAdmin.Components.Form.Input.Gallery.ImagePreview do
  use Surface.Component
  use Phoenix.HTML

  import Ecto.Changeset

  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Form.Input.Image.FocalPoint
  alias BrandoAdmin.Components.Form.MapInputs
  alias Brando.Images
  alias Brando.Utils

  alias Surface.Components.Form.Inputs
  alias Surface.Components.Form.Input.InputContext
  alias Surface.Components.Form.TextInput
  alias Surface.Components.Form.HiddenInput

  prop form, :form
  prop layout, :atom

  data image, :any
  data thumb_url, :string

  def update(assigns, socket) do
    image = assigns.form.source
    sizes = get_field(image, :sizes)
    cdn = get_field(image, :cdn)
    constructed_image = %{sizes: sizes, cdn: cdn}

    require Logger
    Logger.error(inspect(sizes, pretty: true))

    thumb_url =
      if sizes == %{},
        do: nil,
        else: Utils.img_url(constructed_image, :thumb, prefix: Utils.media_url())

    {:ok,
     socket
     |> assign(:image, assigns.form.source.changes)
     |> assign(:thumb_url, thumb_url)}
  end

  def render(assigns) do
    ~F"""
    {#if @thumb_url}
      <img
        width="25"
        height="25"
        src={@thumb_url} />
    {#else}
      <div class="img-placeholder">
        <svg class="spin" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><path fill="none" d="M0 0h24v24H0z"/><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z"/></svg>
      </div>
    {/if}
    """
  end
end
