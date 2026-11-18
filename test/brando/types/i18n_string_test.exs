defmodule Brando.Type.I18nStringTest do
  use ExUnit.Case, async: true

  alias Brando.Type.I18nString

  setup do
    locale = Gettext.get_locale(Brando.Gettext)
    on_exit(fn -> Gettext.put_locale(Brando.Gettext, locale) end)
  end

  describe "plain/1" do
    test "reads text in the default language alone as that text" do
      assert I18nString.plain(%{"en" => "Keep it short"}) == "Keep it short"
      assert I18nString.plain(%{"en" => "Keep it short", "no" => nil}) == "Keep it short"
      assert I18nString.plain(%{"en" => "Keep it short", "no" => " "}) == "Keep it short"
    end

    test "leaves other languages, several and other values as they are" do
      assert I18nString.plain(%{"no" => "Hold den kort"}) == %{"no" => "Hold den kort"}
      both = %{"en" => "Keep it short", "no" => "Hold den kort"}
      assert I18nString.plain(both) == both
      assert I18nString.plain(%{"en" => nil}) == %{"en" => nil}
      assert I18nString.plain("Keep it short") == "Keep it short"
      assert I18nString.plain(nil) == nil
    end
  end

  describe "localized/1" do
    test "reads the admin's language, then the default language, then any" do
      label = %{"en" => "Size", "no" => "Størrelse"}

      Gettext.put_locale(Brando.Gettext, "no")
      assert I18nString.localized(label) == "Størrelse"

      Gettext.put_locale(Brando.Gettext, "sv")
      assert I18nString.localized(label) == "Size"
      assert I18nString.localized(%{"no" => "Størrelse", "en" => ""}) == "Størrelse"
    end

    test "passes a plain string through, and gives nil for nothing" do
      assert I18nString.localized("Size") == "Size"
      assert I18nString.localized(nil) == nil
      assert I18nString.localized(%{"en" => " "}) == nil
    end
  end
end
