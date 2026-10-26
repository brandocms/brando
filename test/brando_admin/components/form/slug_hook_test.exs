defmodule BrandoAdmin.Components.Form.SlugHookTest do
  # The server's slug for a title is the Slug hook's. The expected slugs are
  # what npm slugify 1.6.9 gives in Node, called as the hook calls it
  # (`slugify.extend({'/': '-'})`, `{lower: true, strict: true}`).
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form.SlugHook

  doctest SlugHook

  @hook_slugs [
    {"Mat & drikke", "mat-and-drikke"},
    {"Q&A", "qanda"},
    {"50% rabatt", "50percent-rabatt"},
    {"Rock | Roll", "rock-or-roll"},
    {"Pris i € og $", "pris-i-euro-og-dollar"},
    {"Brand®", "brandr"},
    {"Brand™ news", "brandtm-news"},
    {"© 2026 Studio", "c-2026-studio"},
    {"20° i skyggen", "20-i-skyggen"},
    {"½ pris", "pris"},
    {"Vent…og se", "ventog-se"},
    {"中文标题", ""},
    {"a < b > c", "a-less-b-greater-c"},
    {"Æble på træ", "aeble-pa-trae"},
    {"Straße", "strasse"},
    {"Første sak", "forste-sak"},
    {"Hello Wörld/Foo", "hello-world-foo"},
    {"a_b.c", "abc"},
    {"  A -- b ", "a-b"},
    {"Emoji 🎉 fest", "emoji-fest"},
    {"«Sitat» – svar", "sitat-svar"},
    {"Ünïcödé Çafé", "unicode-cafe"},
    {"Привет мир", "privet-mir"},
    {"Ελληνικά", "ellhnika"},
    {"tab\there nbsp", "tab-here-nbsp"},
    {"It's “quoted”", "its-quoted"},
    {"x+y=z", "xyz"},
    {"#1 hit", "1-hit"}
  ]

  # The port is of one version's character map: another needs porting again
  test "the hook's slugify is pinned to the ported version" do
    package = "assets/package.json" |> File.read!() |> Jason.decode!()
    assert package["dependencies"]["slugify"] == "1.6.9"
  end

  test "slugify/1 gives the hook's slug" do
    assert Enum.map(@hook_slugs, fn {title, _} -> {title, SlugHook.slugify(title)} end) == @hook_slugs
  end

  # The hook's camelCase, run in Node
  test "camel_case/1 gives the hook's" do
    cases = [
      {"Straße/æ-rø!", "straßeaeRo"},
      {"Primary color blå", "primaryColorBla"},
      {"ß", "ß"},
      {"Ærlig talt ðx ×", "aErligTaltðx×"}
    ]

    assert Enum.map(cases, fn {title, _} -> {title, SlugHook.camel_case(title)} end) == cases
  end
end
