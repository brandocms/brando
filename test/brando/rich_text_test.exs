defmodule Brando.RichTextTest do
  use ExUnit.Case, async: true
  alias Brando.RichText
  alias Brando.Blueprint.Forms.RichText, as: Configuration
  alias Brando.Villain.Blocks.TextBlock.Data

  test "shared client/server URL fixtures" do
    for fixture <- "test/fixtures/rich_text/urls.json" |> File.read!() |> Jason.decode!() do
      assert RichText.allowed_uri?(fixture["input"]) == fixture["allowed"]

      result =
        case RichText.normalize_url(fixture["input"]) do
          {:ok, url} -> url
          {:error, _} -> nil
        end

      assert result == fixture["normalized"]
    end
  end

  test "module params distinguish no tools from legacy default tools" do
    for {params, expected} <- [{[""], []}, {[nil], ["all"]}, {nil, nil}, {["all"], ["all"]}] do
      cs = Data.changeset(%Data{}, %{extensions: params})
      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :extensions) == expected
    end
  end

  test "URLs share the editor's supported forms and reject executable/obfuscated schemes" do
    for url <- [
          "https://example.com",
          "/rooms",
          "../rooms",
          "#getting-here",
          "mailto:hello@example.com",
          "tel:+4712345678"
        ] do
      assert RichText.allowed_uri?(url)
    end

    for url <- [
          "javascript:void(0)",
          "data:text/html,x",
          "java\nscript:alert(1)",
          "vbscript:x",
          "https:\\evil.test",
          "https://exa mple.com"
        ] do
      refute RichText.allowed_uri?(url)
    end

    assert {:ok, "https://example.com/path"} = RichText.normalize_url(" example.com/path ")
    assert {:ok, "./example.com/path"} = RichText.normalize_url("./example.com/path")
  end

  test "changed rich text is validated without stripping supported HTML" do
    html =
      ~s|<p class="lede"><span id="getting-here" data-type="jump-anchor"><a class="action-button extra" href="/rooms" data-identifier-id="12">Rooms</a></span><sup data-footnote-uid="note-1">•</sup></p>|

    changeset = Data.changeset(%Data{}, %{text: html})
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :text) == html

    for unsafe <- [
          ~s|<a href="javascript:void(0)">bad</a>|,
          ~s|<p onclick="alert(1)">bad</p>|,
          "<script>bad</script>",
          ~s|<p style="background:url(https://example.com)">bad</p>|
        ] do
      refute Data.changeset(%Data{}, %{text: unsafe}).valid?
    end
  end

  test "identifier rewrites parse attributes and escape URLs correctly" do
    html =
      "<p><a data-identifier-id='12' class='action-button' href='/old'>Keep &amp; wording</a> <a href='/old' data-identifier-id='13'>Other</a></p>"

    assert {:updated, updated} = RichText.update_identifier_url(html, 12, "/new?a=1&b=2")
    assert updated =~ ~s|href="/new?a=1&amp;b=2"|
    assert updated =~ "Keep &amp; wording"
    assert updated =~ ~s|href="/old" data-identifier-id="13"|
    assert :unchanged = RichText.update_identifier_url(updated, 12, "/new?a=1&b=2")
    assert :unchanged = RichText.update_identifier_url(html, 12, "javascript:void(0)")
  end

  test "presets add to explicit configuration and never include blockquote" do
    assert "color" in Configuration.add_preset(["p", "color"], :basic)
    assert "orderedList" in Configuration.add_preset(["p", "color"], :basic)
    assert [] == Configuration.resolve([])
    assert [] == Configuration.resolve("")
    assert Configuration.defaults() == Configuration.resolve(nil)
    refute "blockquote" in Configuration.defaults()
    for {_name, extensions} <- Configuration.presets(), do: refute("blockquote" in extensions)
  end

  test "style labels are independent of CSS identity; duplicate definitions are rejected" do
    styles = [%{element: "span", class: "foo-bar", label: "One"}, %{element: "span", class: "foo_bar", label: "Two"}]
    assert Data.changeset(%Data{}, %{styles: styles}).valid?
    refute Data.changeset(%Data{}, %{styles: styles ++ [hd(styles)]}).valid?

    assert [%{"element" => "span", "class" => "small-caps"}] =
             Data.normalize_styles([%{element: "span", class: "small-caps"}])
  end
end
