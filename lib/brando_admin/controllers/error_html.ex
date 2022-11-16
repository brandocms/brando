defmodule Brando.ErrorHTML do
  @moduledoc """
  Basic error views for Brando.
  """

  use BrandoAdmin, :html
  import Brando.Gettext

  embed_templates "error_html/*"

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def template_not_found(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
