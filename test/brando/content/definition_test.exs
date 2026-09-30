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
             %{"label" => %{"en" => "Light"}, "value" => "light"},
             %{"label" => %{"en" => "Dark"}, "value" => "dark"}
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
    source = exported |> Path.join("**/*.exs") |> Path.wildcard() |> hd()
    [{module, _}] = Code.compile_file(source)
    assert {:ok, ^bundle} = Definitions.from_modules([module], root: exported)
  end

  test "export names files by namespace and name, and only digests names that collide", %{path: path} do
    only_english = String.replace(@source, ~s(name en: "Hero", no: "Topp"), ~s(name en: "Hero"))
    File.write!(Path.join(path, "hero.exs"), only_english)

    File.write!(
      Path.join(path, "twin.exs"),
      only_english |> String.replace("Example.Hero", "Example.Twin") |> String.replace(~s("hero-test"), ~s("hero-twin"))
    )

    File.write!(
      Path.join(path, "plain.exs"),
      only_english
      |> String.replace("Example.Hero", "Example.Plain")
      |> String.replace(~s("hero-test"), ~s("plain-test"))
      |> String.replace(~s(name en: "Hero"), ~s(name en: "Plain Text"))
      |> String.replace(~s(namespace en: "Sections"\n), "")
    )

    assert {:ok, bundle} = Definitions.read(path)
    names = bundle |> Writer.files() |> Map.keys()

    assert "plain-text.exs" in names
    assert "plain-text.heex" in names
    assert "modules.lock.json" in names
    twins = Enum.filter(names, &String.starts_with?(&1, "sections/hero-"))
    assert length(twins) == 4
    assert Enum.all?(twins, &(&1 =~ ~r/^sections\/hero-[0-9a-f]{8}\.(exs|heex)$/))

    exported = Path.join(path, "export")
    Writer.write!(bundle, exported)
    plain = File.read!(Path.join(exported, "plain-text.exs"))
    assert plain =~ "defmodule BrandoDefinitions.PlainText do"
    assert plain =~ ~s(template_file :heex, "plain-text.heex")
    assert {:ok, ^bundle} = Definitions.read(exported)
  end

  test "child modules are written in a folder beside their parent, whatever their namespace", %{path: path} do
    only_english = String.replace(@source, ~s(name en: "Hero", no: "Topp"), ~s(name en: "Hero"))

    child = fn module, uid, name, children ->
      only_english
      |> String.replace("Example.Hero", module)
      |> String.replace(~s("hero-test"), ~s("#{uid}"))
      |> String.replace(~s(name en: "Hero"), ~s(name en: "#{name}"))
      |> String.replace(~s(namespace en: "Sections"), ~s(namespace en: "Elsewhere"))
      |> String.replace("  refs do", children <> "\n  refs do")
    end

    File.write!(
      Path.join(path, "hero.exs"),
      String.replace(
        only_english,
        "  refs do",
        "  multi true\n  children do\n    child \"card-test\"\n  end\n\n  refs do"
      )
    )

    File.write!(
      Path.join(path, "card.exs"),
      child.("Example.Card", "card-test", "Card", "  multi true\n  children do\n    child \"badge-test\"\n  end\n")
    )

    File.write!(Path.join(path, "badge.exs"), child.("Example.Badge", "badge-test", "Badge", ""))

    assert {:ok, bundle} = Definitions.read(path)
    names = bundle |> Writer.files() |> Map.keys()

    assert "sections/hero.exs" in names
    assert "sections/hero/card.exs" in names
    assert "sections/hero/card.heex" in names
    assert "sections/hero/card/badge.exs" in names
    refute Enum.any?(names, &String.starts_with?(&1, "elsewhere/"))

    exported = Path.join(path, "export")
    Writer.write!(bundle, exported)

    assert File.read!(Path.join(exported, "sections/hero/card.exs")) =~
             "defmodule BrandoDefinitions.Sections.Hero.Card do"

    assert {:ok, ^bundle} = Definitions.read(exported)
  end

  test "text-ref presets, styles and footnotes round-trip through the definition files", %{path: path} do
    source =
      String.replace(@source, "refs do", """
      refs do
        ref :body, :text do
          config extensions: ["p", "color", "list", "orderedList"], footnotes: true,
            styles: [%{element: "span", class: "small-caps", label: "Small caps"}]
          default text: "<p>Default words</p>"
        end
      """)

    File.write!(Path.join(path, "text.exs"), source)
    assert {:ok, bundle} = Definitions.read(path)
    exported = Path.join(path, "exported")
    Writer.write!(bundle, exported)
    assert {:ok, ^bundle} = Definitions.read(exported)
    data = hd(hd(bundle["modules"])["refs"])["data"]["data"]
    assert data["extensions"] == ["p", "color", "list", "orderedList"]
    assert data["footnotes"]
    assert hd(data["styles"])["class"] == "small-caps"
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

  test "Markdown source and version tokens round-trip without being cast to local IDs", %{path: path} do
    spec = fixture_spec(path)

    ref = %{
      name: :document,
      type: :markdown_source,
      default: %{source_id: "document", policy: :pinned, version_id: "revision"}
    }

    bundle = Model.from_specs!([%{spec | refs: [ref]}], path)
    output = Path.join(path, "markdown")
    Writer.write!(bundle, output)
    assert {:ok, ^bundle} = Definitions.read(output)
    assert get_in(bundle, ["modules", Access.at(0), "refs", Access.at(0), "data", "data", "source_id"]) == "document"

    bad = put_in(ref, [:default, :source_id], 123)

    assert_raise Brando.Content.Definition.Error, ~r/source_id/, fn ->
      Model.from_specs!([%{spec | refs: [bad]}], path)
    end
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
