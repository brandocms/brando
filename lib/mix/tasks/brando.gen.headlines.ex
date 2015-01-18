defmodule Mix.Tasks.Brando.Gen.Headlines do
  use Mix.Task
  alias Phoenix.Naming
  import Mix.Brando

  @shortdoc "Generates files for Headlines."

  @moduledoc """
  Creates a new Headlines controller.
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
    Don't forget to add your new controller to your web/router.ex.

    For frontend:
        headlines_frontend "/posts", #{controller_name}Controller

    For backend, stick the headlines_backend inside your admin scope:
        scope "/admin" do
          pipe_through :admin
          headlines_backend "/posts", #{controller_name}Controller
        end

    application_name = #{application_name}
    ------------------------------------------------------------------
    """
  end

  defp template_dir do
    Application.app_dir(:brando, "priv/templates/headlines")
  end
end