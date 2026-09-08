defmodule Brando.Content.DefinitionTest do
  use ExUnit.Case, async: false

  alias Brando.Content.Definition.{Model, Reader, Writer}
  alias Brando.Content.Definitions

  @source ~S'''
  defmodule Example.Hero do
    use Brando.Content.Definition
    uid "hero-test"
    name en: "Hero", no: "Topp"
    namespace en: "Sections"
    help_text en: "Introduction"
    class "hero"

    refs do
      ref :heading, :header do
        description "Headline"
        config level: 1
        default text: "Hello"
      end
    end

    vars do
      var :theme, :select do
        label "Theme"
        default "light"
        placement :config
        width :half
        options [{"Light", "light"}, {"Dark", "dark"}]
      end
    end

    template :heex, ~S"<section class={@theme}><.ref block={@block} ref={:heading} /></section>"
  end
  '''

  setup do
    path = Path.join(System.tmp_dir!(), "brando-definition-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    %{path: path}
  end

  test "literal files and Spark modules produce the same complete definition", %{path: path} do
    file = Path.join(path, "hero.exs")
    File.write!(file, @source)
    spec = Reader.read!(file)
    expected = Model.from_specs!([spec], path)
    [{module, _}] = Code.compile_file(file)
    assert {:ok, ^expected} = Definitions.from_modules([module], root: path)
    [hero] = expected["modules"]
    assert hero["name"] == %{"en" => "Hero", "no" => "Topp"}
    assert hd(hero["refs"])["data"]["data"]["text"] == "Hello"
    assert hd(hero["vars"])["placement"] == "config"

    assert hd(hero["vars"])["options"] == [
             %{"label" => "Light", "value" => "light"},
             %{"label" => "Dark", "value" => "dark"}
           ]
  end

  test "canonical export reads back identically and deterministically", %{path: path} do
    File.write!(Path.join(path, "hero.exs"), @source)
    assert {:ok, bundle} = Definitions.read(path)
    exported = Path.join(path, "export")
    Writer.write!(bundle, exported)
    assert {:ok, imported} = Definitions.read(exported)
    assert imported == bundle
    assert Writer.files(imported) == Writer.files(bundle)
    source = exported |> Path.join("*.exs") |> Path.wildcard() |> hd()
    [{module, _}] = Code.compile_file(source)
    assert {:ok, ^bundle} = Definitions.from_modules([module], root: exported)
  end

  test "the file loader does not execute expressions", %{path: path} do
    File.write!(
      Path.join(path, "hero.exs"),
      String.replace(@source, "uid \"hero-test\"", "uid File.read!(\"/etc/passwd\")")
    )

    assert {:error, message} = Definitions.read(path)
    assert message =~ "only literals"
  end

  test "all available ref types and var types round-trip with their schema settings", %{path: path} do
    spec = fixture_spec(path)

    refs =
      Brando.Villain.Blocks.list_blocks()
      |> Enum.filter(fn {_type, schema} -> Code.ensure_loaded?(schema) end)
      |> Enum.map(fn {type, _schema} -> %{name: type, type: type, config: [], default: [], assets: []} end)

    vars =
      ~w(boolean string text html image video gallery datetime color select file link date)
      |> Enum.map(fn type ->
        %{key: type, type: type, label: type, settings: %{width: nil, placement: nil}, assets: []}
      end)

    spec = %{spec | refs: refs, vars: vars}
    bundle = Model.from_specs!([spec], path)
    output = Path.join(path, "all-types")
    Writer.write!(bundle, output)
    assert {:ok, ^bundle} = Definitions.read(output)
  end

  test "nested media templates preserve content, options and empty arrays", %{path: path} do
    spec = fixture_spec(path)

    ref = %{
      name: :visual,
      type: :media,
      config: [
        available_blocks: ["picture", "gallery"],
        template_picture: %{title: "Cover", formats: []},
        template_gallery: %{
          display: "list",
          allowed_types: ["image"],
          gallery_object_overrides: [%{object_id: "cover-object", object_type: "image", title: "Override"}]
        }
      ]
    }

    bundle = Model.from_specs!([%{spec | refs: [ref]}], path)
    output = Path.join(path, "nested")
    Writer.write!(bundle, output)
    assert {:ok, ^bundle} = Definitions.read(output)
  end

  test "rejects unknown settings, duplicate identities and dependency cycles", %{path: path} do
    spec = fixture_spec(path)

    for source <- [
          String.replace(@source, "config level: 1", "config typo: 1"),
          String.replace(@source, "uid \"hero-test\"", "uid \"hero-test\"\nuid \"duplicate\""),
          String.replace(@source, "class \"hero\"", "class \"hero\"\nmulti true\nchildren do\nchild \"hero-test\"\nend")
        ] do
      File.write!(spec.source, source)
      assert {:error, _} = Definitions.read(path)
    end
  end

  test "template paths cannot escape the bundle or traverse symlinks", %{path: path} do
    spec = fixture_spec(path)
    original = File.read!(spec.source)
    source = Regex.replace(~r/  template :heex, .*/, original, "  template_file :heex, \"../outside.heex\"")
    File.write!(spec.source, source)
    assert {:error, message} = Definitions.read(path)
    assert message =~ "escapes"
    File.ln_s!("/private/tmp", Path.join(path, "linked"))
    File.write!(spec.source, String.replace(source, "../outside.heex", "linked/outside.heex"))
    assert {:error, message} = Definitions.read(path)
    assert message =~ "symlinks"
  end

  defp fixture_spec(path) do
    file = Path.join(path, "hero.exs")
    File.write!(file, @source)
    Reader.read!(file)
  end
end
