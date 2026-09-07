if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Template do
    @doc false
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    # Pending consumer templates participate in composition. Packaged defaults
    # remain the final fallback.
    def render(igniter, directory, name, binding, override \\ nil) do
      local = override || Path.join(["priv", "templates", directory, name])

      cond do
        Path.type(local) != :relative or ".." in Path.split(local) ->
          {:error, "Template paths must be relative to the project: #{local}"}

        Igniter.exists?(igniter, local) ->
          igniter = Igniter.include_existing_file(igniter, local, source_handler: Rewrite.Source)
          template = igniter.rewrite |> Rewrite.source!(local) |> Rewrite.Source.get(:content)
          {:ok, igniter, EEx.eval_string(template, binding, file: local)}

        override ->
          {:error, "Template #{local} does not exist."}

        true ->
          path = Application.app_dir(:brando, Path.join(["priv", "templates", directory, name]))
          {:ok, igniter, EEx.eval_file(path, binding)}
      end
    rescue
      error -> {:error, "Could not render #{directory}/#{name}: #{Exception.message(error)}"}
    end
  end
else
  defmodule Mix.Brando.Igniter.Template do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
