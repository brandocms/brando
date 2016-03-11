defmodule ReleaseManager.Plugin.ReleaseTasks do
  @name "release_tasks"
  @shortdoc "Generates an escript to invoke <%= application_module %>.ReleaseTasks"

  use ReleaseManager.Plugin
  alias ReleaseManager.Utils

  def before_release(_), do: nil

  def after_release(%Config{name: name}) do
    File.write(Utils.rel_dest_path([name, "bin", "release_tasks.escript"]), """
      #!/usr/bin/env escript
      %%! -config running-config/sys.config
      main(Args) -> 'Elixir.<%= application_module %>.ReleaseTasks':main(Args).
      """)
  end

  def after_cleanup(_), do: nil

  def after_package(_), do: nil
end
