defmodule Brando.Villain.LiquexParser.Builder do
  @moduledoc false

  defmacro __using__(_) do
    quote location: :keep do
      import NimbleParsec

      tag_module = fn name -> Module.concat(["Brando", "Villain", "Tags", name]) end

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
        Liquex.Tag.AssignTag,
        Liquex.Tag.BreakTag,
        Liquex.Tag.CaptureTag,
        Liquex.Tag.CaseTag,
        Liquex.Tag.CommentTag,
        Liquex.Tag.ContinueTag,
        Liquex.Tag.CycleTag,
        Liquex.Tag.EchoTag,
        Liquex.Tag.ForTag,
        Liquex.Tag.IfTag,
        Liquex.Tag.IncrementTag,
        Liquex.Tag.InlineCommentTag,
        Liquex.Tag.LiquidTag,
        Liquex.Tag.ObjectTag,
        Liquex.Tag.RawTag,
        Liquex.Tag.RenderTag,
        Liquex.Tag.TablerowTag,
        Liquex.Tag.UnlessTag
      ]

      tags_parser =
        (custom_tags ++ Enum.map(built_in_tags, &{&1, &1.parse()}))
        |> Enum.map(fn {renderer, parser} -> tag(parser, {:tag, renderer}) end)

      Enum.each(built_in_tags, &Code.ensure_loaded!/1)

      liquid_tags_parser =
        built_in_tags
        |> Enum.filter(&function_exported?(&1, :parse_liquid_tag, 0))
        |> Enum.map(&tag(&1.parse_liquid_tag(), {:tag, &1}))
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

      defcombinatorp(:document, repeat(base))
      defcombinatorp(:liquid_tag_contents, repeat(liquid_tags_parser))

      defparsec(:parse, parsec(:document) |> eos())
    end
  end
end
