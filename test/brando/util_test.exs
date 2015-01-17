defmodule Brando.UtilTest do
  use ExUnit.Case
  import Brando.Util

  test "slugify basic stripping/no ending dash" do
    assert(slugify("This is basic functionality!!!    ") == "this-is-basic-functionality")
  end

  test "slugify no starting dash" do
    assert(slugify("-This is basic functionality!!!    ") == "this-is-basic-functionality")
  end

  test "slugify straße" do
    assert slugify("straße") == "strasse"
  end

  test "slugify strips symbols" do
    assert slugify("Is ♬ ♫ ♪ ♩ a melody or just noise?") == "is-a-melody-or-just-noise"
  end

  test "slugify strips accents" do
    assert slugify("Àddîñg áçćèńtš tô Éñgłïśh íš śīłłÿ!") == "adding-accents-to-english-is-silly"
  end

  test "slugify special characters" do
    assert(slugify("special characters (#?@$%^*) are also ASCII") == "special-characters-are-also-ascii")
  end

  test "slugify & -> and" do
    assert(slugify("tom & jerry") == "tom-and-jerry")
  end

  test "slugify strip extraneous dashes" do
    assert(slugify("so - just one then?") == "so-just-one-then")
  end
end