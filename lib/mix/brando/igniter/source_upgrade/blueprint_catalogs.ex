if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.BlueprintCatalogs do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # A Blueprint translates through its `gettext_module`, by default
    # `<Application>Admin.Gettext`, whose catalogs live under the backend's
    # `priv:` (default `priv/gettext`). 0.53 sites often keep a frontend
    # backend beside it (`priv/gettext/frontend`), and copies of a Blueprint's
    # catalogs there are read by nothing.

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Module, as: ProjectModule
    alias Sourceror.Zipper

    @doc """
    `{:ok, privs}`, the catalog directories the Gettext backend the
    Blueprint in `zipper` translates through may use, or `:unknown` when one
    cannot be read. Each directory a config file of any environment sets is
    a candidate, since which environment's config applies is not the task's
    to know, and translations go to each; with none set, the backend's own
    `priv:` decides.
    """
    def priv(igniter, zipper) do
      with {:ok, backend} <- gettext_module(zipper),
           {:ok, {igniter, _source, backend_zipper}} <- ProjectModule.find_module(igniter, backend),
           {:ok, configured} <- config_privs(igniter, backend) do
        candidates(configured, backend_zipper)
      else
        _ -> :unknown
      end
    end

    # Config replaces the `use` option; without any, the option decides.
    defp candidates([], backend_zipper), do: with({:ok, own} <- backend_priv(backend_zipper), do: {:ok, [own]})
    defp candidates(configured, _backend_zipper), do: {:ok, Enum.uniq(configured)}

    # The backend's application config, `config :my_app, MyApp.Gettext,
    # priv: "…"`, which Gettext merges over the `use` options: `{:ok, privs}`
    # in every config file, or `:unknown` when one sets `priv:` to anything
    # but a literal. Read from the config calls themselves, so commented-out
    # config is not.
    defp config_privs(igniter, backend) do
      igniter = Igniter.include_glob(igniter, "config/*.exs")

      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.filter(&(Path.dirname(&1.path) == "config" and Path.extname(&1.path) == ".exs"))
      |> Enum.sort_by(& &1.path)
      |> Enum.flat_map(&backend_config_calls(Rewrite.Source.get(&1, :content), backend))
      |> Enum.map(&options_config_priv/1)
      |> Enum.reject(&(&1 == :none))
      |> then(fn found -> if :unknown in found, do: :unknown, else: {:ok, for({:ok, priv} <- found, do: priv)} end)
    end

    # The options of each `config _app, backend, options` call in `content`.
    defp backend_config_calls(content, backend) do
      case Code.string_to_quoted(content) do
        {:ok, ast} ->
          {_ast, calls} = Macro.prewalk(ast, [], &collect_config_call(&1, &2, backend))
          calls

        _error ->
          [:unreadable]
      end
    end

    defp collect_config_call({:config, _, [_app, {:__aliases__, _, parts}, options]} = node, calls, backend) do
      if Module.concat(parts) == backend, do: {node, calls ++ [options]}, else: {node, calls}
    end

    defp collect_config_call(node, calls, _backend), do: {node, calls}

    defp options_config_priv(options) when is_list(options) do
      case if(Keyword.keyword?(options), do: Keyword.fetch(options, :priv), else: {:ok, :unreadable}) do
        {:ok, priv} when is_binary(priv) -> {:ok, String.trim_trailing(priv, "/")}
        {:ok, _expression} -> :unknown
        :error -> :none
      end
    end

    defp options_config_priv(_options), do: :unknown

    @doc "Whether `po_path` (`<priv>/<locale>/LC_MESSAGES/<domain>.po`) is in one of `privs`."
    def in_priv?(_po_path, :unknown), do: true
    def in_priv?(po_path, {:ok, privs}), do: (po_path |> Path.dirname() |> Path.dirname() |> Path.dirname()) in privs

    defp gettext_module(zipper) do
      with {:ok, options} <- use_options(zipper) do
        case Igniter.Code.Keyword.get_key(options, :gettext_module) do
          {:ok, value} -> alias_module(Zipper.node(value))
          :error -> admin_gettext(options)
        end
      end
    end

    defp alias_module({:__aliases__, _, parts}), do: {:ok, Module.concat(parts)}
    defp alias_module(_ast), do: :error

    defp admin_gettext(options) do
      with {:ok, value} <- Igniter.Code.Keyword.get_key(options, :application),
           {:__block__, _, [application]} when is_binary(application) <- Zipper.node(value) do
        {:ok, Module.concat(["#{application}Admin", "Gettext"])}
      else
        _ -> :error
      end
    end

    defp use_options(zipper) do
      with {:ok, body} <- Common.move_to_do_block(zipper),
           {:ok, use_zipper} <- Igniter.Code.Module.move_to_use(body, Brando.Blueprint) do
        CodeFunction.move_to_nth_argument(use_zipper, 1)
      end
    end

    defp backend_priv(zipper) do
      with {:ok, body} <- Common.move_to_do_block(zipper),
           {:ok, use_zipper} <- backend_use(body) do
        case CodeFunction.move_to_nth_argument(use_zipper, 1) do
          {:ok, options} -> options_priv(options)
          :error -> {:ok, "priv/gettext"}
        end
      else
        _ -> :unknown
      end
    end

    defp options_priv(options) do
      case {Igniter.Code.Keyword.get_key(options, :backend), Igniter.Code.Keyword.get_key(options, :priv)} do
        # `use Gettext, backend: …` uses a backend; it is not one.
        {{:ok, _backend}, _priv} -> :unknown
        {:error, {:ok, value}} -> literal_priv(Zipper.node(value))
        {:error, :error} -> {:ok, "priv/gettext"}
      end
    end

    defp literal_priv({:__block__, _, [priv]}) when is_binary(priv), do: {:ok, String.trim_trailing(priv, "/")}
    defp literal_priv(_ast), do: :unknown

    defp backend_use(body) do
      case Igniter.Code.Module.move_to_use(body, Gettext.Backend) do
        {:ok, use_zipper} -> {:ok, use_zipper}
        :error -> Igniter.Code.Module.move_to_use(body, Gettext)
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.BlueprintCatalogs do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
