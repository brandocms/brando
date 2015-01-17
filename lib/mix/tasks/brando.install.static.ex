defmodule Mix.Tasks.Brando.Install.Static do
  use Mix.Task
  alias Phoenix.Naming
  import Mix.Brando

  @shortdoc "Copies static files for Brando."

  @moduledoc """
  Copies all needed static files for Brando
  """

  def run(args) do
    run(args, nil)
  end

  def run(_, _opts) do
    application_atom   = Mix.Project.config()[:app]
    application_name   = Naming.camelize(application_atom)
    copy_from static_dir, Path.join("./", "priv/static"), application_name, &File.read!(&1)
    Mix.shell.info """
    """
  end

  def brando_template_dir do
    Application.app_dir(:brando, "priv/templates/brando")
  end

  def users_template_dir do
    Application.app_dir(:brando, "priv/templates/users")
  end

  def static_dir do
    Application.app_dir(:brando, "priv/static")
  end
end