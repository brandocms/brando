defmodule Mix.Tasks.Brando.Install.Headlines do
  use Mix.Task
  alias Phoenix.Naming
  import Mix.Brando

  @shortdoc "Generates files for Headlines."

  @moduledoc """
  Creates a new Headlines controller.
  """

  @doc """
  Copies Headlines files from template directory to OTP app.
  """
  def run(args) do
    run(args, nil)
  end
  def run(_, _opts) do
    application_atom   = Mix.Project.config()[:app]
    application_name   = Naming.camelize(application_atom)
    controller = "post"
    controller_name = Naming.camelize(controller)

    binding = [application_atom: application_atom,
               application_name: application_name,
               controller: controller,
               controller_name: controller_name]

    copy_from template_dir, "./", {}, &EEx.eval_file(&1, binding)
    Mix.shell.info """
    ------------------------------------------------------------------
    Brando finished copying.
    ------------------------------------------------------------------
    """
  end

  defp template_dir do
    Application.app_dir(:brando, "priv/templates/headlines")
  end
end