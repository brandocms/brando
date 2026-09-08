defmodule Brando.GettextTest do
  use ExUnit.Case, async: true

  alias Expo.Message
  alias Expo.Message.{Plural, Singular}
  alias Expo.PO

  @gettext_path Path.expand("../../priv/gettext", __DIR__)

  test "Norwegian catalogs cover every extracted message with complete translations" do
    for template <- Path.wildcard(Path.join(@gettext_path, "*.pot")) do
      domain = Path.basename(template, ".pot")
      path = Path.join([@gettext_path, "no", "LC_MESSAGES", "#{domain}.po"])
      translations = path |> PO.parse_file!() |> Map.fetch!(:messages) |> Map.new(&{Message.key(&1), &1})

      for source <- PO.parse_file!(template).messages, not source.obsolete do
        translation = Map.get(translations, Message.key(source))
        label = "#{domain}: #{IO.iodata_to_binary(source.msgid)}"

        assert translation, "Missing Norwegian message: #{label}"
        refute translation.obsolete, "Obsolete Norwegian message: #{label}"
        refute Message.has_flag?(translation, "fuzzy"), "Unreviewed Norwegian translation: #{label}"

        case {source, translation} do
          {%Singular{}, %Singular{msgstr: text}} ->
            assert_translation(source.msgid, text, domain, label)

          {%Plural{}, %Plural{msgstr: forms}} ->
            assert Map.keys(forms) |> Enum.sort() == [0, 1], "Missing Norwegian plural forms: #{label}"
            assert_translation(source.msgid, forms[0], domain, label)
            assert_translation(source.msgid_plural, forms[1], domain, label)
        end
      end
    end
  end

  defp assert_translation(source, text, domain, label) do
    assert String.trim(IO.iodata_to_binary(text)) != "", "Empty Norwegian translation: #{label}"
    # The mutations domain uses action keys (create/update/delete), with a
    # `singular` binding supplied by Form rather than embedded in the msgid.
    expected = if domain == "mutations", do: placeholders("%{singular}"), else: placeholders(source)
    assert expected == placeholders(text), "Mismatched Norwegian interpolation keys: #{label}"
  end

  defp placeholders(text) do
    ~r/%\{(\w+)\}/
    |> Regex.scan(IO.iodata_to_binary(text), capture: :all_but_first)
    |> MapSet.new()
  end
end
