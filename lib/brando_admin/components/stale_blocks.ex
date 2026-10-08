defmodule BrandoAdmin.Components.StaleBlocks do
  @moduledoc """
  The module editor's notice that some of the module's blocks are on an
  older version, with the way to resolve them
  (`BrandoAdmin.Content.StaleBlocksLive`).
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  attr :count, :integer, required: true
  attr :module_id, :integer, required: true

  def notice(%{count: 0} = assigns), do: ~H""

  def notice(assigns) do
    ~H"""
    <div class="stale-blocks-notice" role="status">
      <.icon name="triangle-alert" />
      <p class="stale-blocks-notice-headline">
        {ngettext("%{count} block on an older version", "%{count} blocks on older versions", @count)}
      </p>
      <.link
        navigate={"/admin/config/content/modules/update/#{@module_id}/stale-blocks"}
        class="stale-blocks-notice-action"
      >
        {gettext("Resolve blocks")}
      </.link>
      <p class="stale-blocks-notice-explanation">
        {ngettext(
          "It holds references or variables this module no longer defines, so saving the module cannot bring it up to date.",
          "They hold references or variables this module no longer defines, so saving the module cannot bring them up to date.",
          @count
        )}
      </p>
    </div>
    """
  end
end
