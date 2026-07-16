defmodule Brando.Blueprint.Trait do
  @moduledoc false

  defmacro trait(name, opts \\ []) do
    trait = expand_trait(name, __CALLER__)
    {requested_compiler, trait_opts} = Keyword.pop(opts, :compile_with)
    compiler = expand_compiler(requested_compiler, trait, __CALLER__)

    [
      compiler.generate_code(__CALLER__.module, trait_opts),
      quote location: :keep, generated: true do
        Module.put_attribute(__MODULE__, :traits, {unquote(trait), unquote(trait_opts)})
      end
    ]
  end

  defp expand_trait(:sequenced, _caller), do: sequenced_trait()
  defp expand_trait(:status, _caller), do: built_in_trait("Status")
  defp expand_trait(:timestamped, _caller), do: built_in_trait("Timestamped")
  defp expand_trait(name, caller), do: Macro.expand(name, caller)

  defp expand_compiler(nil, trait, _caller) do
    if trait in compiler_traits() do
      trait
      |> Module.concat("Compiler")
      |> ensure_compiler!()
    else
      trait
    end
  end

  defp expand_compiler(compiler, _trait, caller) do
    compiler
    |> Macro.expand(caller)
    |> ensure_compiler!()
  end

  defp ensure_compiler!(compiler) do
    Code.ensure_compiled!(compiler)

    if function_exported?(compiler, :generate_code, 2) do
      compiler
    else
      raise CompileError,
        description: "#{inspect(compiler)} must define generate_code/2 to compile a Blueprint trait"
    end
  end

  defp compiler_traits,
    do: [sequenced_trait(), built_in_trait("Status"), built_in_trait("Timestamped")]

  defp sequenced_trait, do: Module.concat(["Brando", "Trait", "Sequenced"])
  defp built_in_trait(name), do: Module.concat(["Brando", "Trait", name])
end
