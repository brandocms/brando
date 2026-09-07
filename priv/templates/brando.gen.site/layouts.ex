defmodule <%= web_module %>.CMS.Layouts do
  use BrandoWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={@language}>
      <.head conn={@conn} />
      <.body_tag conn={@conn} id="top">
        {@inner_content}
      </.body_tag>
    </html>
    """
  end
end
