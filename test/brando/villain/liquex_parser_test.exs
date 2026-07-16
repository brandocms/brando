defmodule Brando.Villain.LiquexParserTest do
  use ExUnit.Case, async: true

  alias Brando.Villain.LiquexParser

  test "split built-in grammars retain base Liquex parsing parity" do
    templates = [
      "{% assign value = 'one' %}{{ value }}",
      "{% break %}{% continue %}",
      "{% capture value %}Hello {{ entry.title }}{% endcapture %}",
      "{% case value %}{% when 'one' %}One{% else %}Other{% endcase %}",
      "{% comment %}{{ ignored }}{% endcomment %}",
      "{% cycle 'one', 'two' %}",
      "{% echo entry.title %}",
      "{% for item in items %}{{ item }}{% else %}Empty{% endfor %}",
      "{% if entry.visible %}Visible{% else %}Hidden{% endif %}",
      "{% increment counter %}",
      "{% # this is an inline comment %}",
      "{% liquid\nassign value = 'one'\necho value\n%}",
      "{{ entry.title }}",
      "{% raw %}{{ untouched }}{% endraw %}",
      "{% render 'card' %}",
      "{% tablerow item in items %}{{ item }}{% endtablerow %}",
      "{% unless entry.hidden %}Visible{% endunless %}"
    ]

    for template <- templates do
      assert {:ok, expected} = Liquex.parse(template, Liquex.Parser.Base)
      assert {:ok, ^expected} = Liquex.parse(template, LiquexParser)
    end
  end

  test "built-in block tags recurse into Brando custom tags" do
    template = "{% if entry.visible %}{% ref refs.title %}{% endif %}"

    assert {:ok,
            [
              {{:tag, Liquex.Tag.IfTag},
               [
                 expression: _expression,
                 contents: [{{:tag, Brando.Villain.Tags.Ref}, [ref: _ref]}]
               ]}
            ]} = Liquex.parse(template, LiquexParser)
  end
end
