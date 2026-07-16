defmodule Brando.Villain.LiquexParser.BuiltInTags.Simple do
  @moduledoc false

  use Brando.Villain.LiquexParser.BuiltInTagGroup,
    tags: [
      {Liquex.Tag.AssignTag, :assign, :assign_liquid},
      {Liquex.Tag.BreakTag, :break, :break_liquid},
      {Liquex.Tag.ContinueTag, :continue, :continue_liquid},
      {Liquex.Tag.EchoTag, :echo, :echo_liquid},
      {Liquex.Tag.IncrementTag, :increment, :increment_liquid},
      {Liquex.Tag.InlineCommentTag, :inline_comment, :inline_comment_liquid},
      {Liquex.Tag.ObjectTag, :object, nil},
      {Liquex.Tag.RenderTag, :render, :render_liquid}
    ]
end
