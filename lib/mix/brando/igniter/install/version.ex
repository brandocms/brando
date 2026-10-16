if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Install.Version do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Code.Module, as: CodeModule
    alias Igniter.Project.MixProject
    alias Rewrite.Source

    @attribute ~s[@version "VERSION" |> File.read!() |> String.trim()]

    @doc """
    Keeps the application's version in a `VERSION` file that `mix.exs` reads.

    Florist reads the version of the release it builds from `VERSION`, falling
    back to a literal `@version "..."` in `mix.exs`; phx.new writes neither, only
    an inline `version: "0.1.0"`. A literal version, inline or in `@version`,
    moves to a new `VERSION` file. An existing `VERSION` is kept: `mix.exs` is
    pointed at it when its literal version agrees, and a notice reports a
    disagreement. A `mix.exs` that already reads `VERSION`, or computes its
    version some other way, is left unchanged.
    """
    def plan(igniter) do
      {igniter, file} = version_file(igniter)

      case {mix_version(igniter), file} do
        {:reads_file, _} -> igniter
        {{:literal, version, at}, nil} -> igniter |> create(version) |> read_file(at)
        {{:literal, version, at}, version} -> read_file(igniter, at)
        {{:literal, version, _at}, file} -> disagreement(igniter, version, file)
        {:other, _} -> other_notice(igniter, file)
      end
    end

    defp create(igniter, version), do: Igniter.create_new_file(igniter, "VERSION", version <> "\n")

    defp read_file(igniter, :inline) do
      igniter
      |> MixProject.update(:project, [:version], fn _ -> {:ok, {:code, quote(do: @version)}} end)
      |> Igniter.update_elixir_file("mix.exs", fn zipper ->
        # move_to_def/3 lands in the function body; the attribute goes before the def.
        with {:ok, body} <- CodeFunction.move_to_def(zipper, :project, 0),
             {:ok, project} <- Common.move_upwards(body, &CodeFunction.function_call?(&1, :def, 2)) do
          {:ok, Common.add_code(project, @attribute, placement: :before)}
        end
      end)
    end

    defp read_file(igniter, {:attribute, name}) do
      Igniter.update_elixir_file(igniter, "mix.exs", fn zipper ->
        with {:ok, attribute} <- CodeModule.move_to_attribute_definition(zipper, name) do
          code = String.replace_prefix(@attribute, "@version", "@#{name}")
          {:ok, Common.replace_code(attribute, code)}
        end
      end)
    end

    defp disagreement(igniter, version, file) do
      Igniter.add_notice(igniter, """
      VERSION says #{file} and mix.exs says #{version}; both were left unchanged.
      Florist deploys the version in VERSION. Settle on one and have mix.exs read it:
        #{@attribute}
      """)
    end

    defp other_notice(igniter, file) do
      Igniter.add_notice(igniter, """
      mix.exs computes its version in a way this installer does not change#{if file, do: "", else: ", and there is no VERSION file"}.
      Florist reads the release version from VERSION, so keep it there and have mix.exs read it:
        #{@attribute}
      """)
    end

    defp version_file(igniter) do
      if Igniter.exists?(igniter, "VERSION") do
        igniter = Igniter.include_existing_file(igniter, "VERSION", source_handler: Source)
        {igniter, igniter.rewrite |> Rewrite.source!("VERSION") |> Source.get(:content) |> String.trim()}
      else
        {igniter, nil}
      end
    end

    # The project's `version:`, read from the source without evaluating it.
    defp mix_version(igniter) do
      quoted = igniter.rewrite |> Rewrite.source!("mix.exs") |> Source.get(:content) |> Code.string_to_quoted!()

      case project_keyword(quoted, :version) do
        # An unrelated @version would be shadowed by the one this adds.
        version when is_binary(version) ->
          if attribute_value(quoted, :version) == :missing, do: {:literal, version, :inline}, else: :other

        {:@, _, [{name, _, context}]} when is_atom(context) ->
          attribute(quoted, name)

        value ->
          if reads_version_file?(value), do: :reads_file, else: :other
      end
    end

    defp attribute(quoted, name) do
      case attribute_value(quoted, name) do
        version when is_binary(version) -> {:literal, version, {:attribute, name}}
        value -> if reads_version_file?(value), do: :reads_file, else: :other
      end
    end

    defp project_keyword(quoted, key) do
      {_, found} =
        Macro.prewalk(quoted, :missing, fn
          {:def, _, [{:project, _, args}, [do: body]]} = node, :missing when args in [nil, []] ->
            {node, if(Keyword.keyword?(body), do: Keyword.get(body, key, :missing), else: :missing)}

          node, found ->
            {node, found}
        end)

      found
    end

    defp attribute_value(quoted, name) do
      {_, found} =
        Macro.prewalk(quoted, :missing, fn
          {:@, _, [{^name, _, [value]}]} = node, :missing -> {node, value}
          node, found -> {node, found}
        end)

      found
    end

    defp reads_version_file?(value) do
      {_, found?} =
        Macro.prewalk(value, false, fn
          "VERSION" = node, _ -> {node, true}
          node, found? -> {node, found?}
        end)

      found?
    end
  end
else
  defmodule Mix.Brando.Igniter.Install.Version do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
