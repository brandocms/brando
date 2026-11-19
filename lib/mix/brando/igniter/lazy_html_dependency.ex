if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.LazyHTMLDependency do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    # Brando parses HTML with lazy_html at runtime, and lists it as optional,
    # as Phoenix LiveView does, so fetching Brando does not diverge from the
    # `{:lazy_html, ">= 0.1.0", only: :test}` that `mix phx.new` writes. The
    # application's own line then has to cover every environment: this drops
    # its `only:`, or adds `Brando.HTML.Tree.dependency/0` when there is none.

    alias Igniter.Code.Common
    alias Igniter.Code.Function
    alias Igniter.Code.Module, as: CodeModule
    alias Igniter.Code.Tuple, as: CodeTuple
    alias Mix.Brando.Igniter.Dependencies

    @only ~r/,\s*only:\s*(:\w+|\[[^\]]*\])/

    @doc """
    Makes the application's lazy_html a runtime dependency: drops the `only:`
    of the line it has, or adds the line. A deps/0 Igniter cannot read gets a
    notice instead.
    """
    def plan(igniter) do
      case Igniter.Project.Deps.get_dep(igniter, :lazy_html) do
        {:ok, nil} ->
          Dependencies.add_new(igniter, Brando.HTML.Tree.dependency())

        {:ok, declared} ->
          if Regex.match?(@only, declared), do: drop_only(igniter, declared), else: igniter

        _unreadable ->
          by_hand(igniter)
      end
    end

    defp drop_only(igniter, declared) do
      runtime = Regex.replace(@only, declared, "", global: false)

      igniter
      |> Igniter.update_elixir_file("mix.exs", fn zipper ->
        with {:ok, zipper} <- CodeModule.move_to_module_using(zipper, Mix.Project),
             {:ok, zipper} <- Function.move_to_defp(zipper, :deps, 0),
             {:ok, zipper} <- Common.move_to(zipper, &lazy_html?/1) do
          {:ok, Common.replace_code(zipper, runtime)}
        else
          _ -> {:warning, by_hand_message()}
        end
      end)
      |> queue_deps_get()
    end

    defp lazy_html?(zipper) do
      with true <- CodeTuple.tuple?(zipper),
           {:ok, name} <- CodeTuple.tuple_elem(zipper, 0) do
        Common.nodes_equal?(name, :lazy_html)
      else
        _ -> false
      end
    end

    # The lock has lazy_html for tests already; deps.get makes the build for
    # every environment fetch it.
    defp queue_deps_get(igniter) do
      if {"deps.get", []} in igniter.tasks, do: igniter, else: Igniter.add_task(igniter, "deps.get")
    end

    defp by_hand(igniter), do: Igniter.add_notice(igniter, by_hand_message())

    defp by_hand_message do
      """
      Brando parses HTML with lazy_html, which the application lists for every
      environment. Its deps/0 in mix.exs is not one list the installer reads, so
      it was left as it is: add #{inspect(Brando.HTML.Tree.dependency())}, or drop
      `only: :test` from the lazy_html line `mix phx.new` writes.
      """
    end
  end
else
  defmodule Mix.Brando.Igniter.LazyHTMLDependency do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
