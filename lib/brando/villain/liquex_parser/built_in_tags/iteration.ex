defmodule Brando.Villain.LiquexParser.BuiltInTags.Iteration do
  @moduledoc false

  use Brando.Villain.LiquexParser.BuiltInTagGroup,
    bridges: [:document, :liquid_tag_contents],
    tags: [
      {Liquex.Tag.CycleTag, :cycle, :cycle_liquid},
      {Liquex.Tag.ForTag, :for_tag, :for_liquid},
      {Liquex.Tag.TablerowTag, :tablerow, :tablerow_liquid}
    ]
end
