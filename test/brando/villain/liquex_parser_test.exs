defmodule Brando.Villain.LiquexParserTest do
  use ExUnit.Case, async: true

  alias Brando.Villain.LiquexParser
  alias Brando.Villain.Tags.Output

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
      assert {:ok, parsed} = Liquex.parse(template, LiquexParser)
      assert unwrap_outputs(parsed) == expected
    end
  end

  test "an output knows whether template text comes right before and after it" do
    template = ~S(a{{ x }}{{ y }}{% if z %}{% echo w %}b{% endif %})

    assert {:ok,
            [
              {:text, "a"},
              {{:tag, Output}, [tag: Liquex.Tag.ObjectTag, contents: _, after_text: true, before_text: false]},
              {{:tag, Output}, [tag: Liquex.Tag.ObjectTag, contents: _, after_text: false, before_text: false]},
              {{:tag, Liquex.Tag.IfTag},
               [
                 expression: _,
                 contents: [
                   {{:tag, Output}, [tag: Liquex.Tag.EchoTag, contents: _, after_text: false, before_text: true]},
                   {:text, "b"}
                 ]
               ]}
            ]} = Liquex.parse(template, LiquexParser)
  end

  # Brando renders outputs through `Brando.Villain.Tags.Output`
  defp unwrap_outputs({{:tag, Output}, [tag: tag, contents: contents, after_text: _, before_text: _]}),
    do: {{:tag, tag}, unwrap_outputs(contents)}

  defp unwrap_outputs(list) when is_list(list), do: Enum.map(list, &unwrap_outputs/1)
  defp unwrap_outputs({key, value}), do: {unwrap_outputs(key), unwrap_outputs(value)}
  defp unwrap_outputs(other), do: other

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
