if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Template do
    @doc "Requests recompilation when optional Igniter support is removed."
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
          {igniter, template} = read(igniter, local)
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

    @doc """
    `{igniter, content}` of the project's template at `path`, read as text.

    The template is not left in the rewrite: Igniter parses every `.ex`
    source in it when writing, to place modules, and an EEx template named
    `.ex` does not parse.
    """
    def read(igniter, path) do
      included? = Rewrite.has_source?(igniter.rewrite, path)
      igniter = Igniter.include_existing_file(igniter, path, source_handler: Rewrite.Source)
      content = igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

      if included?,
        do: {igniter, content},
        else: {%{igniter | rewrite: Rewrite.delete(igniter.rewrite, path)}, content}
    end
  end
else
  defmodule Mix.Brando.Igniter.Template do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
