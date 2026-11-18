defmodule Brando.Content.DefinitionErrorsTest do
  # brandocms/brando#3541: an invalid definition file says which file, which
  # definition and var, what the field takes and what it got, in place of the
  # raw changeset errors.
  use ExUnit.Case, async: true

  alias Brando.Content.Definition.{Archive, Error}
  alias Brando.Content.Definitions
  alias Brando.Content.{Module, Var}
  alias Ecto.Changeset

  setup do
    path = Path.join(System.tmp_dir!(), "brando-definition-errors-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    %{path: path}
  end

  defp module_source(body, opts \\ []) do
    uid = Keyword.get(opts, :uid, "parrot-text")
    name = Keyword.get(opts, :module, "Example.Tekst")

    """
    defmodule #{name} do
      use Brando.Content.Definition
      uid "#{uid}"
      name en: "Text"
      class "text"
      #{Keyword.get(opts, :options, "")}

    #{body}

      template :heex, ~S"<p>{@label}</p>"
    end
    """
  end

  defp vars(vars), do: "  vars do\n#{vars}\n  end"
  defp refs(refs), do: "  refs do\n#{refs}\n  end"

  defp write!(root, name, source) do
    file = Path.join(root, name)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, source)
    file
  end

  defp read_error(path) do
    assert {:error, message} = Definitions.read(path)
    message
  end

  describe "a definition file's errors" do
    test "name the file relative to the app, the var, what the field takes and what it got" do
      app_relative = Path.join(["tmp", "definition-errors-#{System.unique_integer([:positive])}", "priv", "modules"])
      root = Path.join(File.cwd!(), app_relative)
      on_exit(fn -> File.rm_rf!(Path.dirname(Path.dirname(root))) end)

      write!(
        root,
        "01-tekst/tekst.exs",
        module_source(vars(~s(    var :label, :string do\n      placeholder %{"no" => "Skriv her"}\n    end)))
      )

      assert read_error(root) ==
               ~s|#{app_relative}/01-tekst/tekst.exs: var "label": placeholder must be a string (got a map)|
    end

    test "outside the app, name the file relative to the definition directory", %{path: path} do
      write!(path, "01-tekst/tekst.exs", module_source(vars(~s(    var :label, :string do\n      width :huge\n    end))))

      assert read_error(path) ==
               ~s|01-tekst/tekst.exs: var "label": width must be one of full, half, third, fourth, auto, fill (got "huge")|
    end

    test "a value of the wrong kind says its type and shows the value", %{path: path} do
      write!(path, "tekst.exs", module_source(vars(~s(    var :label, :string do\n      new_row 12\n    end))))
      assert read_error(path) == ~s|tekst.exs: var "label": new_row must be true or false (got the integer 12)|
    end

    test "list every error, one per line", %{path: path} do
      write!(
        path,
        "tekst.exs",
        module_source(vars(~s(    var :label, :string do\n      placeholder ["a"]\n      width :huge\n    end)))
      )

      assert read_error(path) |> String.split("\n") |> Enum.sort() == [
               ~s|tekst.exs: var "label": placeholder must be a string (got a list)|,
               ~s|tekst.exs: var "label": width must be one of full, half, third, fourth, auto, fill (got "huge")|
             ]
    end

    test "a module's own field names no var", %{path: path} do
      write!(path, "tekst.exs", module_source("", options: ~s(multi "often")))
      assert read_error(path) == ~s|tekst.exs: multi must be true or false (got "often")|
    end

    test "a required field in a nested embed of a ref", %{path: path} do
      write!(
        path,
        "tekst.exs",
        module_source(refs(~s(    ref :embed, :html do\n      config params: [%{label: "Id"}]\n    end)))
      )

      assert read_error(path) == ~s(tekst.exs: ref "embed": params[0].key is required)
    end

    test "an inclusion error lists the values allowed", %{path: path} do
      write!(
        path,
        "tekst.exs",
        module_source(refs(~s(    ref :body, :text do\n      config styles: [%{element: "blink", class: "x"}]\n    end)))
      )

      assert read_error(path) ==
               ~s|tekst.exs: ref "body": styles[0].element must be one of p, h1, h2, h3, h4, h5, h6, span (got "blink")|
    end

    test "format and length errors show the value, truncated", %{path: path} do
      long = String.duplicate("a", 80)

      write!(
        path,
        "tekst.exs",
        module_source(
          refs(~s(    ref :embed, :html do\n      config params: [%{key: "Bad Key"}, %{key: "#{long}"}]\n    end))
        )
      )

      lines = path |> read_error() |> String.split("\n")

      assert ~s|tekst.exs: ref "embed": params[0].key must start with a lowercase letter and hold only lowercase letters, digits and _ (got "Bad Key")| in lines

      assert [length] = Enum.filter(lines, &(&1 =~ "params[1].key should be at most 64 character(s)"))
      assert length =~ ~r/\(got "a{20,}…"\)$/
      assert String.length(length) < 160
    end

    test "a custom validation keeps its message", %{path: path} do
      write!(
        path,
        "tekst.exs",
        module_source(refs(~s(    ref :embed, :html do\n      config params: [%{key: "id"}, %{key: "id"}]\n    end)))
      )

      assert read_error(path) == ~s(tekst.exs: ref "embed": params has a key twice)
    end

    test "a table template's var", %{path: path} do
      write!(path, "tables/prices.exs", """
      defmodule Example.Prices do
        use Brando.Content.Definition
        kind :table_template
        uid "prices"
        name "Prices"

        vars do
          var :price, :string do
            placeholder %{"no" => "Pris"}
          end
        end
      end
      """)

      assert read_error(path) == ~s|tables/prices.exs: var "price": placeholder must be a string (got a map)|
    end

    test "a child definition's error names the child's own file", %{path: path} do
      write!(
        path,
        "list.exs",
        module_source("  children do\n    child \"parrot-item\"\n  end",
          uid: "parrot-list",
          module: "Example.List",
          options: "multi true"
        )
      )

      write!(
        path,
        "list/item.exs",
        module_source(vars(~s(    var :label, :string do\n      placeholder %{"no" => "Punkt"}\n    end)),
          uid: "parrot-item",
          module: "Example.Item"
        )
      )

      assert read_error(path) == ~s|list/item.exs: var "label": placeholder must be a string (got a map)|
    end

    test "syntax and other reader errors name the file relative too", %{path: path} do
      write!(path, "tekst.exs", "defmodule Example.Tekst do\n  uid \"x\"\nend\n")
      assert read_error(path) == "tekst.exs: expected use Brando.Content.Definition"
    end
  end

  test "a ZIP's errors name the file within the bundle" do
    zip = fn files ->
      {:ok, {_, binary}} =
        :zip.create(~c"defs.zip", Enum.map(files, fn {name, body} -> {String.to_charlist(name), body} end), [:memory])

      binary
    end

    source = module_source(vars(~s(    var :label, :string do\n      placeholder %{"no" => "Hei"}\n    end)))

    assert {:error, ~s|01-tekst/tekst.exs: var "label": placeholder must be a string (got a map)|} =
             Archive.read(zip.([{"modules/01-tekst/tekst.exs", source}]))
  end

  test "a changeset invalid without errors of its own still says so" do
    changeset = %{Changeset.change(%Var{key: "intro"}) | valid?: false}

    assert_raise Error, ~s(module "x": is invalid), fn -> Error.changeset!(changeset, ~s(module "x")) end
  end

  test "a stored var that no longer reads names the module holding it" do
    # A type the schema no longer has, say
    var = %Var{key: "intro", type: nil, label: %{"en" => "Intro"}}

    assert_raise Error, ~s(module "parrot-text": var "intro": type is required), fn ->
      Brando.Content.Definition.Model.stored_var_record(var, ~s(module "parrot-text"))
    end
  end

  describe "describe/1" do
    test "names a saved definition and its var, with the schema's expected type" do
      changeset =
        struct(Module)
        |> Changeset.change()
        |> Changeset.put_assoc(:vars, [
          %Var{key: "intro"}
          |> Changeset.cast(%{"placeholder" => %{"en" => "x"}}, [:placeholder])
        ])

      assert Error.describe(%{uid: "parrot-text", error: changeset}) ==
               ~s|module "parrot-text": var "intro": placeholder must be a string (got a map)|
    end

    test "a table template is named so" do
      changeset =
        Changeset.add_error(Changeset.change(%Brando.Content.TableTemplate{}), :name, "can't be blank",
          validation: :required
        )

      assert Error.describe(%{uid: "prices", error: changeset}) == ~s(table template "prices": name is required)
    end

    test "an unknown error reads as its message, interpolated, never a raw map" do
      changeset =
        %Var{key: "intro"}
        |> Changeset.change()
        |> Changeset.add_error(:value, "has %{count} problems near %{where}",
          count: 3,
          where: {:line, 2},
          custom: %{a: 1}
        )

      assert Error.describe(%{uid: "x", error: changeset}) ==
               ~s(module "x": var "intro": value has 3 problems near {:line, 2})

      assert Error.describe("already a message") == "already a message"
      assert Error.describe(%{uid: "x", error: :boom}) == "x: :boom"
    end
  end
end
