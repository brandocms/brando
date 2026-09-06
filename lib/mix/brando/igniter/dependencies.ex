if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Dependencies do
    @moduledoc false

    alias Igniter.Project.Deps

    def add_new(igniter, dependency) do
      existing? = Deps.has_dep?(igniter, elem(dependency, 0))
      igniter = Deps.add_dep(igniter, dependency, on_exists: :skip, error?: true, append?: true)

      if existing? or {"deps.get", []} in igniter.tasks do
        igniter
      else
        # Fetch only after acceptance, so the next command can compile generated
        # modules that use the new dependency. A dry run never fetches packages.
        Igniter.add_task(igniter, "deps.get")
      end
    end
  end
end
