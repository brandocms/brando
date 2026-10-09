defmodule Brando.Deprecated.LexicalAliasesTest do
  use ExUnit.Case, async: true

  alias Brando.Deprecated.LexicalAliases

  # `{line, name as written, resolved}` for every module name outside
  # `alias` and `require`, in order, read by both parsers
  defp resolutions(code) do
    from_elixir = code |> Code.string_to_quoted!(columns: true) |> collect()
    from_sourceror = code |> Sourceror.parse_string!() |> collect()
    assert from_elixir == from_sourceror
    from_elixir
  end

  defp collect(ast) do
    {_ast, found} =
      ast
      |> LexicalAliases.annotate()
      |> Macro.prewalk([], fn
        {form, _, _}, acc when form in [:alias, :require] ->
          {:ok, acc}

        {:__aliases__, meta, parts} = node, acc ->
          written =
            Enum.map_join(parts, ".", fn
              {name, _, _} -> name
              name -> name
            end)

          {node, [{meta[:line], written, resolved(meta[:resolved_alias])} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp resolved({:either, a, b}), do: {:either, resolved(a), resolved(b)}
  defp resolved(nil), do: nil
  defp resolved(parts), do: Module.concat(parts)

  test "an alias reaches the code after it, to the end of its module or function" do
    code = """
    defmodule A do
      def before, do: Upload
      alias Brando.Upload
      def after_, do: Upload.Inner

      def local do
        alias Plug.Upload
        Upload
      end

      def again, do: Upload
    end

    defmodule B do
      def other, do: Upload
    end
    """

    assert [
             {1, "A", A},
             {2, "Upload", Upload},
             {4, "Upload.Inner", Brando.Upload.Inner},
             {8, "Upload", Plug.Upload},
             {11, "Upload", Brando.Upload},
             {14, "B", B},
             {15, "Upload", Upload}
           ] = resolutions(code)
  end

  test "as:, require as:, multi-aliases relative to another alias, and nested modules" do
    code = """
    defmodule Outer do
      alias Brando, as: B
      alias B.{Meta, Upload}
      require Brando.Utils, as: U

      defmodule Inner.Deep do
        def x, do: {Meta, Upload, U, __MODULE__.Y}
      end

      def y, do: Inner
    end
    """

    assert [
             {1, "Outer", Outer},
             {6, "Inner.Deep", Outer.Inner.Deep},
             {7, "Meta", Brando.Meta},
             {7, "Upload", Brando.Upload},
             {7, "U", Brando.Utils},
             {7, "__MODULE__.Y", Outer.Inner.Deep.Y},
             {10, "Inner", Outer.Inner}
           ] = resolutions(code)
  end

  test "if and other scoping macros keep their aliases; another macro's block may leak them" do
    code = """
    defmodule A do
      if true do
        alias Plug.Upload
      end

      def a, do: Upload

      settings do
        alias Plug.Upload
      end

      def b, do: Upload
    end
    """

    assert [{1, "A", A}, {6, "Upload", Upload}, {12, "Upload", {:either, Plug.Upload, Upload}}] = resolutions(code)
  end
end
