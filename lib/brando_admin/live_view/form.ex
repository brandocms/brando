defmodule BrandoAdmin.LiveView.Form do
  @moduledoc """
  Public setup API for Brando admin form LiveViews.

  Use the stable entry point in application code:

      use BrandoAdmin.LiveView.Form, schema: MyApp.Projects.Project

  Compiler and hook modules are internal implementation details.
  """

  @hooks Module.concat(["BrandoAdmin", "LiveView", "Form", "Hooks"])

  @doc false
  defmacro __using__(opts), do: BrandoAdmin.LiveView.Form.Compiler.build(opts)

  @doc false
  def on_mount(hook, params, session, socket) do
    call_hooks(:on_mount, [hook, params, session, socket])
  end

  defp call_hooks(function, arguments), do: apply(@hooks, function, arguments)
end
