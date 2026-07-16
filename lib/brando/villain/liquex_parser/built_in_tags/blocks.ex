defmodule Brando.Villain.LiquexParser.BuiltInTags.Blocks do
  @moduledoc false

  use Brando.Villain.LiquexParser.BuiltInTagGroup,
    bridges: [:document, :liquid_tag_contents],
    tags: [
      {Liquex.Tag.CaptureTag, :capture, nil},
      {Liquex.Tag.CommentTag, :comment, nil},
      {Liquex.Tag.LiquidTag, :liquid, :liquid_liquid},
      {Liquex.Tag.RawTag, :raw, nil}
    ]
end
