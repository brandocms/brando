defmodule Brando.Villain.LiquexParser.Builder do
  @moduledoc false

  defmacro __using__(_) do
    quote location: :keep do
      import NimbleParsec

      tag_module = fn name -> Module.concat(["Brando", "Villain", "Tags", name]) end

      built_in_parser = fn name ->
        Module.concat(["Brando", "Villain", "LiquexParser", "BuiltInTags", name])
      end

      custom_tags = [
        {tag_module.("HeadlessRef"), Brando.Villain.LiquexParser.Syntax.headless_ref()},
        {tag_module.("Inspect"), Brando.Villain.LiquexParser.Syntax.inspect_tag()},
        {tag_module.("Ref"), Brando.Villain.LiquexParser.Syntax.ref()},
        {tag_module.("Link"), Brando.Villain.LiquexParser.Syntax.link()},
        {tag_module.("Picture"), Brando.Villain.LiquexParser.Syntax.picture()},
        {tag_module.("Video"), Brando.Villain.LiquexParser.Syntax.video()},
        {tag_module.("Route"), Brando.Villain.LiquexParser.Syntax.route()},
        {tag_module.("RouteI18n"), Brando.Villain.LiquexParser.Syntax.route_i18n()},
        {tag_module.("Fragment"), Brando.Villain.LiquexParser.Syntax.fragment()},
        {tag_module.("Hide"), Brando.Villain.LiquexParser.Syntax.hide()},
        {tag_module.("EndHide"), Brando.Villain.LiquexParser.Syntax.end_hide()},
        {tag_module.("T"), Brando.Villain.LiquexParser.Syntax.translation()},
        {tag_module.("Datasource"), Brando.Villain.LiquexParser.Syntax.datasource()},
        {tag_module.("EndDatasource"), Brando.Villain.LiquexParser.Syntax.end_datasource()}
      ]

      built_in_tags = [
        {Liquex.Tag.AssignTag, built_in_parser.("Simple"), :assign, :assign_liquid},
        {Liquex.Tag.BreakTag, built_in_parser.("Simple"), :break, :break_liquid},
        {Liquex.Tag.CaptureTag, built_in_parser.("Blocks"), :capture, nil},
        {Liquex.Tag.CaseTag, built_in_parser.("Conditionals"), :case_tag, :case_liquid},
        {Liquex.Tag.CommentTag, built_in_parser.("Blocks"), :comment, nil},
        {Liquex.Tag.ContinueTag, built_in_parser.("Simple"), :continue, :continue_liquid},
        {Liquex.Tag.CycleTag, built_in_parser.("Iteration"), :cycle, :cycle_liquid},
        {Liquex.Tag.EchoTag, built_in_parser.("Simple"), :echo, :echo_liquid},
        {Liquex.Tag.ForTag, built_in_parser.("Iteration"), :for_tag, :for_liquid},
        {Liquex.Tag.IfTag, built_in_parser.("Conditionals"), :if_tag, :if_liquid},
        {Liquex.Tag.IncrementTag, built_in_parser.("Simple"), :increment, :increment_liquid},
        {Liquex.Tag.InlineCommentTag, built_in_parser.("Simple"), :inline_comment, :inline_comment_liquid},
        {Liquex.Tag.LiquidTag, built_in_parser.("Blocks"), :liquid, :liquid_liquid},
        {Liquex.Tag.ObjectTag, built_in_parser.("Simple"), :object, nil},
        {Liquex.Tag.RawTag, built_in_parser.("Blocks"), :raw, nil},
        {Liquex.Tag.RenderTag, built_in_parser.("Simple"), :render, :render_liquid},
        {Liquex.Tag.TablerowTag, built_in_parser.("Iteration"), :tablerow, :tablerow_liquid},
        {Liquex.Tag.UnlessTag, built_in_parser.("Conditionals"), :unless_tag, :unless_liquid}
      ]

      tags_parser =
        (custom_tags ++
           Enum.map(built_in_tags, fn {renderer, parser_module, parser, _liquid_parser} ->
             {renderer, parsec({parser_module, parser})}
           end))
        |> Enum.map(fn {renderer, parser} -> tag(parser, {:tag, renderer}) end)

      liquid_tags_parser =
        built_in_tags
        |> Enum.reject(fn {_renderer, _parser_module, _parser, liquid_parser} -> is_nil(liquid_parser) end)
        |> Enum.map(fn {renderer, parser_module, _parser, liquid_parser} ->
          tag(parsec({parser_module, liquid_parser}), {:tag, renderer})
        end)
        |> choice()

      leading_whitespace =
        empty()
        |> Liquex.Parser.Literal.whitespace(1)
        |> lookahead(choice([string("{%-"), string("{{-")]))
        |> ignore()

      base =
        choice(
          tags_parser ++
            [
              Liquex.Parser.Literal.text(),
              leading_whitespace
            ]
        )

      # Exported for the split built-in parsers, whose recursive block tags
      # call back into the complete document grammar.
      defcombinator(:document, repeat(base))
      defcombinator(:liquid_tag_contents, repeat(liquid_tags_parser))

      defparsec(:parse, parsec(:document) |> eos())
    end
  end
end
