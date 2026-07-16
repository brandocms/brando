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

  defp expand_trait(:creator, _caller), do: built_in_trait("Creator")
  defp expand_trait(:ensure_uid, _caller), do: built_in_trait("EnsureUID")
  defp expand_trait(:meta, _caller), do: built_in_trait("Meta")
  defp expand_trait(:scheduled_publishing, _caller), do: built_in_trait("ScheduledPublishing")
  defp expand_trait(:sequenced, _caller), do: sequenced_trait()
  defp expand_trait(:soft_delete, _caller), do: built_in_trait("SoftDelete")
  defp expand_trait(:status, _caller), do: built_in_trait("Status")
  defp expand_trait(:timestamped, _caller), do: built_in_trait("Timestamped")
  defp expand_trait(:translatable, _caller), do: built_in_trait("Translatable")
  defp expand_trait(:validate_var_keys, _caller), do: built_in_trait("ValidateVarKeys")
  defp expand_trait(name, caller), do: Macro.expand(name, caller)

  defp expand_compiler(nil, trait, _caller) do
    cond do
      trait in compiler_traits() ->
        trait
        |> Module.concat("Compiler")
        |> ensure_compiler!()

      trait in runtime_only_traits() ->
        built_in_trait("NoopCompiler")
        |> ensure_compiler!()

      true ->
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
    do: [
      built_in_trait("Creator"),
      built_in_trait("Meta"),
      built_in_trait("ScheduledPublishing"),
      sequenced_trait(),
      built_in_trait("SoftDelete"),
      built_in_trait("Status"),
      built_in_trait("Timestamped"),
      built_in_trait("Translatable")
    ]

  defp runtime_only_traits,
    do: [
      built_in_trait("EnsureUID"),
      built_in_trait("ValidateVarKeys")
    ]

  defp sequenced_trait, do: Module.concat(["Brando", "Trait", "Sequenced"])
  defp built_in_trait(name), do: Module.concat(["Brando", "Trait", name])
end
