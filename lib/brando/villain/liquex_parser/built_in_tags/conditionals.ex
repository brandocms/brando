defmodule Brando.Villain.LiquexParser.BuiltInTags.Conditionals do
  @moduledoc false

  use Brando.Villain.LiquexParser.BuiltInTagGroup,
    bridges: [:document, :liquid_tag_contents],
    tags: [
      {Liquex.Tag.CaseTag, :case_tag, :case_liquid},
      {Liquex.Tag.IfTag, :if_tag, :if_liquid},
      {Liquex.Tag.UnlessTag, :unless_tag, :unless_liquid}
    ]
end
