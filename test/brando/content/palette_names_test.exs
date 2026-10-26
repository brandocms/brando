defmodule Brando.Content.PaletteNamesTest do
  # A palette's key and namespace, and its colours' keys, name the section
  # attribute and the CSS custom properties its colours are written to, in the
  # page and in the palettes stylesheet.
  use Brando.ConnCase, async: false

  import Brando.Test.Support, only: [preserve_cache: 1]

  alias Brando.Content
  alias Brando.Content.Palette
  alias Brando.Factory

  # Stored before names and values were checked: each would leave its
  # attribute, declaration or `<style>` element, marking the document.
  @breakout_key ~s(x" data-marked="key)
  @breakout_namespace ~s(ns"><img data-marked="namespace)
  @breakout_color_key ~s(bg;}</style><b data-marked="color-key">)
  @breakout_hex ~s(red}</style><b data-marked="hex">)

  setup do
    preserve_cache([:palettes, :palettes_css])
    {:ok, user: Factory.insert(:random_user)}
  end

  defp params(attrs) do
    Map.merge(
      %{
        status: :published,
        name: "Dark",
        key: "darkSection",
        namespace: "site",
        colors: [%{name: "Background", key: "bg", hex_value: "#000000"}]
      },
      attrs
    )
  end

  defp stored_palette(attrs) do
    Factory.insert(
      :palette,
      Map.merge(
        %{
          status: :published,
          colors: [%Palette.Color{name: "Background", key: "bg", hex_value: "#000000"}]
        },
        attrs
      )
    )
  end

  describe "changeset" do
    test "accepts letters in any script, digits, - and _", %{user: user} do
      for {key, namespace, color_key} <- [
            {"darkSection", "site", "bg"},
            {"dark-section_2", "general", "color_bg"},
            {"mørk", "seksjon", "bakgrunn-blå"}
          ] do
        assert {:ok, palette} =
                 Content.create_palette(
                   params(%{
                     key: key,
                     namespace: namespace,
                     colors: [%{name: "Background", key: color_key, hex_value: "#000000"}]
                   }),
                   user
                 )

        assert {palette.key, palette.namespace, hd(palette.colors).key} == {key, namespace, color_key}
      end
    end

    test "refuses a key or namespace that is not a CSS name", %{user: user} do
      for value <- ["dark section", @breakout_key, "a}b", "a:b"] do
        assert {:error, changeset} = Content.create_palette(params(%{key: value}), user)
        assert changeset.errors[:key]

        assert {:error, changeset} = Content.create_palette(params(%{namespace: value}), user)
        assert changeset.errors[:namespace]
      end
    end

    test "refuses a colour key that is not a CSS name", %{user: user} do
      assert {:error, changeset} =
               Content.create_palette(
                 params(%{colors: [%{name: "Background", key: @breakout_color_key, hex_value: "#000000"}]}),
                 user
               )

      assert [%{errors: [key: _]}] = changeset.changes.colors
    end

    test "a stored key or namespace is kept when other fields change", %{user: user} do
      palette = stored_palette(%{key: "Dark section", namespace: "old namespace"})

      assert {:ok, updated} = Content.update_palette(palette, %{name: "Renamed"}, user)
      assert {updated.key, updated.namespace} == {"Dark section", "old namespace"}
    end
  end

  describe "css_escape/1" do
    test "keeps a valid name and escapes everything else as six hex digits" do
      assert Palette.css_escape("bakgrunn-blå_2") == "bakgrunn-blå_2"
      assert Palette.css_escape("a b") == "a\\000020b"
      assert Palette.css_escape(~s(x"]{)) == "x\\000022\\00005D\\00007B"
      assert Palette.css_escape(nil) == ""
    end
  end

  describe "rendered container" do
    test "a stored palette's names stay inside the section attribute and style" do
      palette =
        stored_palette(%{
          key: @breakout_key,
          namespace: @breakout_namespace,
          colors: [
            %Palette.Color{name: "Background", key: @breakout_color_key, hex_value: "#000000"},
            %Palette.Color{name: "Text", key: "fg", hex_value: @breakout_hex},
            %Palette.Color{name: "Accent", key: "accent", hex_value: "#ff00ff"}
          ]
        })

      html = render_container(palette, ~s(top" data-marked="anchor))

      refute html =~ ~s(data-marked=")
      refute html =~ "</style>"
      assert html =~ ~s(b-section="ns&quot;&gt;&lt;img data-marked=&quot;namespace-x&quot; data-marked=&quot;key")
      assert html =~ ~s(id="top&quot; data-marked=&quot;anchor")
      # The colour with a value stored before values were checked is left out
      assert html =~ ~s(style="--bg\\00003B\\00007D\\00003C\\00002Fstyle\\00003E\\00003Cb\\000020data-marked)
      refute html =~ "--fg"
      assert html =~ "--accent: #ff00ff"
    end

    test "a valid palette renders as before" do
      palette =
        stored_palette(%{
          key: "green",
          namespace: "general",
          colors: [
            %Palette.Color{name: "Background", key: "color_bg", hex_value: "#000000"},
            %Palette.Color{name: "Text", key: "color_fg", hex_value: "#FFFFFF"}
          ]
        })

      assert render_container(palette, nil) =~
               ~s(<section b-section="general-green" style="--color_bg: #000000;--color_fg: #FFFFFF">)
    end
  end

  describe "palettes stylesheet" do
    test "a stored palette's names and values cannot leave the stylesheet" do
      stored_palette(%{
        key: @breakout_key,
        namespace: @breakout_namespace,
        colors: [
          %Palette.Color{name: "Background", key: @breakout_color_key, hex_value: "#000000"},
          %Palette.Color{name: "Text", key: "fg", hex_value: @breakout_hex}
        ]
      })

      stored_palette(%{
        key: "globalOne",
        namespace: "site",
        global: true,
        colors: [
          %Palette.Color{name: "Background", key: @breakout_color_key, hex_value: "#000000"},
          %Palette.Color{name: "Text", key: "fg", hex_value: @breakout_hex}
        ]
      })

      Brando.Cache.Palettes.set()
      css = Phoenix.HTML.safe_to_string(Brando.Cache.Palettes.get_css())

      refute css =~ "</style>"
      refute css =~ "data-marked=\""
      refute css =~ "red}"
      refute css =~ "--fg"
      refute css =~ "--palette-site-globalOne-fg"
      assert css =~ "--palette-site-globalOne-bg\\00003B"
      assert css =~ ~s([b-section="ns\\000022\\00003E\\00003Cimg)
    end

    test "a stored key with a space still matches its section" do
      palette =
        stored_palette(%{key: "Dark section", namespace: "site", colors: [%Palette.Color{name: "Bg", key: "bg", hex_value: "#000"}]})

      Brando.Cache.Palettes.set()
      css = Phoenix.HTML.safe_to_string(Brando.Cache.Palettes.get_css())

      # CSS reads `\000020` back as the space the attribute holds
      assert css =~ ~s([b-section="site-Dark\\000020section"] {--bg: #000;})
      assert render_container(palette, nil) =~ ~s(b-section="site-Dark section")
    end

    test "a valid palette's CSS is unchanged" do
      stored_palette(%{key: "green", namespace: "general", colors: [%Palette.Color{name: "Bg", key: "color_bg", hex_value: "#000000"}]})

      stored_palette(%{
        key: "brand",
        namespace: "site",
        global: true,
        colors: [%Palette.Color{name: "Bg", key: "main", hex_value: "#ffffff"}]
      })

      Brando.Cache.Palettes.set()
      css = Phoenix.HTML.safe_to_string(Brando.Cache.Palettes.get_css())

      assert css =~ ~s([b-section="general-green"] {--color_bg: #000000;})
      assert css =~ ":root {--palette-site-brand-main: #ffffff;}"
    end
  end

  test "the Container palette select labels show stored names as text" do
    stored_palette(%{
      name: ~s(Dark <img data-marked="name">),
      key: "dark",
      namespace: @breakout_namespace,
      colors: [%Palette.Color{name: "Text", key: "fg", hex_value: @breakout_hex}]
    })

    labels = Enum.map_join(Brando.Content.Container.get_palettes(nil, nil), & &1.label)

    refute labels =~ "data-marked=\""
    refute labels =~ "</style>"
    assert labels =~ "Dark &lt;img data-marked=&quot;name&quot;&gt;"
  end

  defp render_container(palette, anchor) do
    block = %{
      block: %{
        type: :container,
        source: "Elixir.Brando.Pages.Page.Blocks",
        palette_id: palette.id,
        anchor: anchor,
        container_id: nil,
        uid: Brando.Utils.generate_uid(),
        children: []
      }
    }

    Brando.Villain.parse([block], %Brando.Pages.Page{})
  end
end
