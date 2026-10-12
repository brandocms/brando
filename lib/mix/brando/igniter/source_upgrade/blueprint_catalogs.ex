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
    `{:ok, priv}`, the catalog directory of the Gettext backend the
    Blueprint in `zipper` translates through, or `:unknown` when the
    backend's source cannot be read.
    """
    def priv(igniter, zipper) do
      with {:ok, backend} <- gettext_module(zipper),
           {:ok, {igniter, _source, backend_zipper}} <- ProjectModule.find_module(igniter, backend) do
        case config_priv(igniter, backend) do
          :none -> backend_priv(backend_zipper)
          priv -> priv
        end
      else
        _ -> :unknown
      end
    end

    # The backend's application config, `config :my_app, MyApp.Gettext,
    # priv: "…"`, which Gettext merges over the `use` options: `{:ok, priv}`,
    # `:unknown` when it sets `priv:` to anything but a literal, or `:none`.
    defp config_priv(igniter, backend) do
      igniter = Igniter.include_glob(igniter, "config/*.exs")
      call = ~r/\bconfig\s*\(?\s*:\w+\s*,\s*#{Regex.escape(inspect(backend))}\s*,(.*?)(?=\n(?!\s)|\z)/s

      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.filter(&(Path.dirname(&1.path) == "config" and Path.extname(&1.path) == ".exs"))
      |> Enum.flat_map(&Regex.scan(call, Rewrite.Source.get(&1, :content), capture: :all_but_first))
      |> Enum.map(fn [options] -> options_config_priv(options) end)
      |> Enum.reject(&(&1 == :none))
      |> Enum.reverse()
      |> case do
        [] -> :none
        [latest | _] = found -> if :unknown in found, do: :unknown, else: latest
      end
    end

    defp options_config_priv(options) do
      case Regex.run(~r/\bpriv:\s*"([^"\\#]+)"\s*(?:[,\])]|\z)/, options) do
        [_, priv] -> {:ok, String.trim_trailing(priv, "/")}
        nil -> if options =~ ~r/\bpriv:/, do: :unknown, else: :none
      end
    end

    @doc "Whether `po_path` (`<priv>/<locale>/LC_MESSAGES/<domain>.po`) is in `priv`."
    def in_priv?(_po_path, :unknown), do: true
    def in_priv?(po_path, {:ok, priv}), do: po_path |> Path.dirname() |> Path.dirname() |> Path.dirname() == priv

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
