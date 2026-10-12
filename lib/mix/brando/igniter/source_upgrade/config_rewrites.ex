if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.ConfigRewrites do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # Configuration that Phoenix 1.8 and current Elixir expect, in sites that
    # predate them:
    #
    #   * Phoenix 1.8's code reloader needs `listeners: [Phoenix.CodeReloader]`
    #     in `project/0`; without it, boot warns that its Mix listener is
    #     missing.
    #   * `use Mix.Config` is deprecated for `import Config`.
    #   * Logger's `:warn` level is deprecated for `:warning`.

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.MixProject
    alias Rewrite.Source
    alias Sourceror.Zipper

    @use_mix_config ~r/^([ \t]*)use Mix\.Config\b/m
    @level_keys [:level, :level_lower_than, :compile_time_purge_level]

    def upgrade(igniter) do
      igniter
      |> add_code_reloader_listener()
      |> rewrite_config_files()
    end

    defp add_code_reloader_listener(igniter) do
      if Igniter.Project.Deps.has_dep?(igniter, :phoenix) do
        MixProject.update(igniter, :project, [:listeners], fn
          nil -> {:ok, {:code, quote(do: [Phoenix.CodeReloader])}}
          zipper -> add_listener(zipper)
        end)
      else
        igniter
      end
    end

    defp add_listener(zipper) do
      cond do
        not Igniter.Code.List.list?(zipper) ->
          {:warning,
           "`listeners` in `project/0` of mix.exs is not a list. Add `Phoenix.CodeReloader` to it: Phoenix 1.8's code reloader needs that Mix listener."}

        match?({:ok, _}, Igniter.Code.List.move_to_list_item(zipper, &Common.nodes_equal?(&1, Phoenix.CodeReloader))) ->
          {:ok, zipper}

        true ->
          Igniter.Code.List.append_to_list(zipper, quote(do: Phoenix.CodeReloader))
      end
    end

    defp rewrite_config_files(igniter) do
      igniter = Igniter.include_glob(igniter, "config/*.exs")

      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.map(&Source.get(&1, :path))
      |> Enum.filter(&(Path.dirname(&1) == "config" and Path.extname(&1) == ".exs"))
      |> Enum.sort()
      |> Enum.reduce(igniter, fn path, igniter ->
        igniter
        |> import_config(path)
        |> logger_levels(path)
      end)
    end

    defp import_config(igniter, path) do
      content = igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content)

      if content =~ @use_mix_config,
        do:
          Igniter.update_file(
            igniter,
            path,
            &Source.update(&1, :content, Regex.replace(@use_mix_config, content, "\\1import Config"))
          ),
        else: igniter
    end

    defp logger_levels(igniter, path) do
      quoted = igniter.rewrite |> Rewrite.source!(path) |> Source.get(:quoted)

      if quoted |> Zipper.zip() |> Common.find_all(&warn_level?/1) == [] do
        igniter
      else
        Igniter.update_elixir_file(igniter, path, fn zipper ->
          Common.update_all_matches(zipper, &warn_level?/1, fn zipper ->
            {:ok,
             Zipper.update(zipper, fn {key, {:__block__, meta, [:warn]}} -> {key, {:__block__, meta, [:warning]}} end)}
          end)
        end)
      end
    end

    # A `level: :warn` pair (or another level key) in a `config :logger` call.
    defp warn_level?(zipper) do
      match?({{:__block__, _, [key]}, {:__block__, _, [:warn]}} when key in @level_keys, Zipper.node(zipper)) and
        in_logger_config?(zipper)
    end

    defp in_logger_config?(nil), do: false

    defp in_logger_config?(zipper) do
      if CodeFunction.function_call?(zipper, :config, :any),
        do: match?({:config, _, [{:__block__, _, [:logger]} | _]}, Zipper.node(zipper)),
        else: in_logger_config?(Zipper.up(zipper))
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.ConfigRewrites do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
