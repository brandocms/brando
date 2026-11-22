defmodule Brando.Content.DefinitionsPalettesContainersTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.{Container, Definitions, Palette}
  alias Brando.{Factory, Repo}

  @fixtures "test/fixtures/definitions/styles"

  setup do
    user = Factory.insert(:random_user)
    path = Path.join(System.tmp_dir!(), "brando-styles-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    %{user: user, path: path}
  end

  defp fixtures!(path, names) do
    for name <- names, do: File.cp!(Path.join(@fixtures, name <> ".exs.txt"), Path.join(path, name <> ".exs"))
    path
  end

  defp palette!(user, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          "name" => "Paper",
          "namespace" => "site",
          "key" => "paper",
          "global" => true,
          "instructions" => "For quiet sections",
          "status" => "published",
          "colors" => [
            %{"name" => "Background", "key" => "background", "hex_value" => "#fff9f4", "instructions" => "Behind"},
            %{"name" => "Text", "key" => "foreground", "hex_value" => "#000000"}
          ]
        },
        attrs
      )

    {:ok, palette} = Brando.Content.create_palette(params, user)
    palette
  end

  defp container!(user, palette, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          "name" => "Tinted section",
          "namespace" => "Sections",
          "code" => ~s(<section b-section="site-paper">{{ content }}</section>),
          "type" => "liquid",
          "allow_custom_palette" => true,
          "palette_namespace" => "site",
          "palette_id" => palette && palette.id
        },
        attrs
      )

    {:ok, container} = Brando.Content.create_container(params, user)
    container
  end

  describe "files" do
    test "a palette and a container read into definitions; the container names its palette by uid", c do
      assert {:ok, bundle} = Definitions.read(fixtures!(c.path, ~w(paper tinted)))

      assert [
               %{
                 "kind" => "palette",
                 "uid" => "acme-palette-paper",
                 "name" => "Paper",
                 "namespace" => "site",
                 "key" => "paper",
                 "global" => false,
                 "instructions" => nil,
                 "colors" => [
                   %{"key" => "background", "hex_value" => "#fff9f4", "name" => "Background"} = background,
                   %{"key" => "foreground", "name" => "Text", "instructions" => nil}
                 ]
               }
             ] = bundle["palettes"]

      assert background["instructions"] == "Behind the text"

      assert [
               %{
                 "kind" => "container",
                 "uid" => "acme-container-tinted",
                 "namespace" => "Sections",
                 "type" => "liquid",
                 "code" => ~s(<section b-section="site-paper">{{ content }}</section>),
                 "allow_custom_palette" => false,
                 "palette" => "acme-palette-paper"
               }
             ] = bundle["containers"]

      assert bundle["modules"] == [] and bundle["table_templates"] == []
    end

    test "a container may name its palette by the palette's module name", c do
      fixtures!(c.path, ~w(paper))

      File.write!(Path.join(c.path, "tinted.exs"), """
      defmodule MySite.Tinted do
        use Brando.Content.Definition
        kind :container
        uid "tinted"
        name "Tinted"
        namespace "Sections"
        palette MySite.Definitions.Palettes.Paper
        template :liquid, "{{ content }}"
      end
      """)

      assert {:ok, %{"containers" => [%{"palette" => "acme-palette-paper"}]}} = Definitions.read(c.path)
    end

    test "each kind declares only what it holds, and a palette's names are what the schema stores", c do
      cases = [
        {~s(kind :palette\n  uid "p"\n  name "P"\n  key "p"\n  template :liquid, "x"),
         "palette definitions don't declare a template"},
        {~s(kind :palette\n  uid "p"\n  name "P"\n  key "p"\n  class "x"), "unsupported palette options [:class]"},
        {~s(kind :container\n  uid "c"\n  name "C"\n  namespace "N"\n  colors do\n    color :a, "#000000"\n  end\n  template :liquid, "x"),
         "container definitions don't declare colors"},
        {~s(uid "m"\n  name "M"\n  key "k"\n  template :liquid, "x"), "unsupported module options [:key]"},
        {~s(kind :palette\n  uid "p"\n  name en: "P"\n  key "p"), "name"},
        {~s(kind :palette\n  uid "p"\n  name "P"\n  key "not a css name"), "key"},
        {~s(kind :palette\n  uid "p"\n  name "P"\n  key "p"\n  colors do\n    color :a, "#000000" do\n      name "A"\n    end\n    color :a, "#ffffff" do\n      name "B"\n    end\n  end),
         "color keys"}
      ]

      for {body, expected} <- cases do
        File.write!(Path.join(c.path, "one.exs"), "defmodule One do\n  use Brando.Content.Definition\n  #{body}\nend\n")
        assert {:error, message} = Definitions.read(c.path)
        assert message =~ expected
      end
    end

    test "compiled definitions build the same bundle as their files", c do
      assert {:ok, read} = Definitions.read(fixtures!(c.path, ~w(paper tinted)))

      [{palette, _}] = Code.compile_file(Path.join(c.path, "paper.exs"))
      [{container, _}] = Code.compile_file(Path.join(c.path, "tinted.exs"))

      assert {:ok, compiled} = Definitions.from_modules([palette, container], root: c.path)
      assert compiled["palettes"] == read["palettes"]
      assert compiled["containers"] == read["containers"]
    end
  end

  describe "export" do
    test "writes every local palette and container, which read back as exported", c do
      palette = palette!(c.user)
      container = container!(c.user, palette)
      # A shared-library override is the library's, and stays out
      palette!(c.user, %{"key" => "override", "name" => "Override"})
      |> Ecto.Changeset.change(source_palette_id: 999_999)
      |> Repo.update!()

      assert {:ok, exported} = Definitions.export(Path.join(c.path, "out"), c.user)
      assert "palettes/paper.exs" in exported.files
      assert "containers/tinted-section.exs" in exported.files
      assert "containers/tinted-section.liquid" in exported.files
      assert [%{"uid" => uid, "colors" => [_, _], "global" => true}] = exported.bundle["palettes"]
      assert uid == palette.uid

      assert [%{"uid" => container_uid, "palette" => ^uid, "allow_custom_palette" => true}] =
               exported.bundle["containers"]

      assert container_uid == container.uid

      source = File.read!(Path.join(exported.directory, "palettes/paper.exs"))
      assert source =~ "kind :palette"
      assert source =~ ~s(color "background", "#fff9f4" do)

      assert File.read!(Path.join(exported.directory, "containers/tinted-section.liquid")) == container.code

      assert {:ok, read} = Definitions.read(exported.directory)
      assert Map.take(read, ~w(palettes containers)) == Map.take(exported.bundle, ~w(palettes containers))
      assert read["baseline"]["palettes"][uid] == exported.bundle["baseline"]["palettes"][uid]
    end

    test "selecting a container brings the palette it names", c do
      palette = palette!(c.user)
      container = container!(c.user, palette)
      palette!(c.user, %{"key" => "other", "name" => "Other"})

      assert {:ok, exported} = Definitions.export(Path.join(c.path, "out"), c.user, uids: [container.uid])
      assert Enum.map(exported.bundle["palettes"], & &1["uid"]) == [palette.uid]
      assert exported.bundle["modules"] == []
    end

    test "a palette or container saved in the admin gets a uid of its own, and so does its copy", c do
      palette = palette!(c.user)
      container = container!(c.user, palette)
      assert is_binary(palette.uid) and is_binary(container.uid)

      assert {:ok, copy} = Brando.Content.duplicate_palette(palette.id, c.user)
      assert copy.uid != palette.uid
      assert {:ok, copy} = Brando.Content.duplicate_container(container.id, c.user)
      assert copy.uid != container.uid
      assert Repo.aggregate(Palette, :count) == 2 and Repo.aggregate(Container, :count) == 2
    end
  end
end
