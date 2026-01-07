defmodule Brando.ErrorHTML do
  @moduledoc """
  Basic error views for Brando.
  """

  require Logger

  use BrandoAdmin, :html
  use Gettext, backend: Brando.Gettext

  embed_templates "error_html/*"

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def template_not_found(template, assigns) do
    if reason = assigns[:reason] do
      Logger.error("""
      Error rendering #{template}:
      #{Exception.format(:error, reason, assigns[:stack] || [])}
      """)
    end

    Phoenix.Controller.status_message_from_template(template)
  end
end
