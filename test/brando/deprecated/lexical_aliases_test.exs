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

  defp resolved({:either, candidates}), do: {:either, Enum.map(candidates, &resolved/1)}
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

    assert [{1, "A", A}, {6, "Upload", Upload}, {12, "Upload", {:either, [Plug.Upload, Upload]}}] = resolutions(code)
  end

  test "each block of a scoping macro starts from the aliases where it is called" do
    code = """
    defmodule A do
      alias Brando.Upload

      def f(x) do
        if x do
          alias Plug.Upload
          Upload
        else
          Upload
        end
      end

      def g do
        try do
          alias Plug.Upload
          Upload
        rescue
          _ -> Upload
        catch
          _ -> Upload
        else
          _ -> Upload
        after
          Upload
        end
      end

      def h do
        alias Plug.Upload
        Upload
      rescue
        _ -> Upload
      end

      def i(x) do
        with {:ok, y} <- x do
          alias Plug.Upload
          {y, Upload}
        else
          _ -> Upload
        end
      end

      def j(x), do: unless(x, do: (alias Plug.Upload; Upload), else: Upload)
    end
    """

    assert [
             {1, "A", A},
             {7, "Upload", Plug.Upload},
             {9, "Upload", Brando.Upload},
             {16, "Upload", Plug.Upload},
             {18, "Upload", Brando.Upload},
             {20, "Upload", Brando.Upload},
             {22, "Upload", Brando.Upload},
             {24, "Upload", Brando.Upload},
             {30, "Upload", Plug.Upload},
             {32, "Upload", Brando.Upload},
             {38, "Upload", Plug.Upload},
             {40, "Upload", Brando.Upload},
             {44, "Upload", Plug.Upload},
             {44, "Upload", Brando.Upload}
           ] = resolutions(code)
  end

  test "a remote call with a do block: Kernel's scoping macros scope it, another macro may leak it" do
    code = """
    defmodule A do
      alias Brando.Upload

      Kernel.if true do
        alias Plug.Upload
      end

      def a, do: Upload

      Some.Dsl.settings do
        alias Plug.Upload
      end

      def b, do: Upload
    end
    """

    assert [
             {1, "A", A},
             {4, "Kernel", Kernel},
             {8, "Upload", Brando.Upload},
             {10, "Some.Dsl", Some.Dsl},
             {14, "Upload", {:either, [Plug.Upload, Brando.Upload]}}
           ] = resolutions(code)
  end

  test "names in a template sigil resolve through the aliases where it is written" do
    code = ~S'''
    defmodule A do
      alias Brando.Meta

      def a(assigns) do
        ~H"""
        <Meta.HTML.render_meta conn={@conn} />
        <.link navigate={Brando.Upload.path()}>Store</.link>
        """
      end

      def b(assigns), do: ~H"<Meta.HTML.x />"
    end
    '''

    for ast <- [Code.string_to_quoted!(code), Sourceror.parse_string!(code)] do
      {_ast, found} =
        ast
        |> LexicalAliases.annotate()
        |> Macro.prewalk([], fn
          {:sigil_H, _, _} = node, acc -> {node, acc ++ LexicalAliases.template_names(node)}
          node, acc -> {node, acc}
        end)

      assert [{[:Brando, :Meta, :HTML], 6}, {[:Brando, :Upload], 7}, {[:Brando, :Meta, :HTML], 11}] =
               Enum.map(found, &{&1.resolved, &1.line})
    end
  end

  test "an alias in a with clause reaches its do block, not its else" do
    code = """
    defmodule A do
      alias Brando.Upload

      def g(x) do
        with alias(Other.W, as: Upload), {:ok, _} <- x do
          Upload
        else
          _ -> Upload
        end
      end
    end
    """

    assert [{1, "A", A}, {6, "Upload", Other.W}, {8, "Upload", Brando.Upload}] = resolutions(code)
  end

  test "an alias of a name that may be either module may be either too" do
    code = """
    defmodule A do
      alias Brando.Upload

      Some.Dsl.settings do
        alias Plug.Upload
      end

      alias Upload, as: U
      alias Upload.{Inner}
      def a, do: {U, Inner}
    end
    """

    assert [
             {1, "A", A},
             {4, "Some.Dsl", Some.Dsl},
             {10, "U", {:either, [Plug.Upload, Brando.Upload]}},
             {10, "Inner", {:either, [Plug.Upload.Inner, Brando.Upload.Inner]}}
           ] = resolutions(code)
  end

  test "template names come from code: interpolations, EEx tags, attributes and component tags" do
    env = %{aliases: %{Upload: %{to: [:Brando, :Upload], at: {2, 3}}}, module: [:A]}

    text = """
    <%!-- Upload comment --%>
    <!-- Upload too -->
    <h1>Store current state, Upload</h1>
    <p>{gettext("Upload anyway")}</p>
    <button label={gettext("Upload files")} :if={Upload.ok?(@x)}>
      {dgettext("x",
        "Upload to %{folder}")}
    </button>
    <Upload.Button.render x={%{a: "}"}} />
    <%= Upload.url(@x) %>
    <% Upload.y() %>
    <script>let x = {Upload: 1}</script>
    """

    assert [
             %{name: "Upload", resolved: [:Brando, :Upload], line: 5},
             %{name: "Upload.Button", resolved: [:Brando, :Upload, :Button], line: 9},
             %{name: "Upload", resolved: [:Brando, :Upload], line: 10},
             %{name: "Upload", resolved: [:Brando, :Upload], line: 11}
           ] = LexicalAliases.names_in_text(text, env, 1)

    # A fragment that does not parse alone keeps its strings' interpolations
    assert [%{line: 1}] = LexicalAliases.names_in_text(~S|<%= if "#{Upload.url(@x)}" != "" do %>x<% end %>|, env, 1)

    # EEx has no {…} interpolation
    assert [%{line: 1}] = LexicalAliases.names_in_text("<%= Upload.x() %> {Upload.y()}", env, 1, :eex)
  end
end
