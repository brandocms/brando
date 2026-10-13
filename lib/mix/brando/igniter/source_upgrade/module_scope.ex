if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.ModuleScope do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # The nodes that belong to one module. `Igniter.Code.Common.find_all/2`
    # walks on past the focused node, into the modules after it in the file,
    # and a module's subtree holds the modules nested in it.

    alias Igniter.Code.Common
    alias Sourceror.Zipper

    @doc """
    The zippers matching `predicate` in the subtree at `zipper`, the focused
    module or module body, leaving out modules nested in it.
    """
    def find_all(zipper, predicate) do
      zipper
      |> Zipper.subtree()
      |> Common.find_all(predicate)
      |> Enum.reject(&nested?/1)
    end

    # Under a `defmodule` other than the subtree's root.
    defp nested?(zipper) do
      case Zipper.up(zipper) do
        nil -> false
        parent -> (defmodule?(Zipper.node(parent)) and not is_nil(Zipper.up(parent))) or nested?(parent)
      end
    end

    defp defmodule?({:defmodule, _, _}), do: true
    defp defmodule?(_node), do: false
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.ModuleScope do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
