defmodule Brando.Villain.LiquexParser.BuiltInTagGroup do
  @moduledoc false

  defmacro __using__(opts) do
    tags = Keyword.fetch!(opts, :tags)
    bridges = Keyword.get(opts, :bridges, [])

    bridge_definitions =
      Enum.map(bridges, fn bridge ->
        bridge_function = :"#{bridge}__0"

        quote do
          defp unquote(bridge_function)(rest, acc, stack, context, line, offset) do
            apply(@parser_module, unquote(bridge_function), [
              rest,
              acc,
              stack,
              context,
              line,
              offset
            ])
          end
        end
      end)

    tag_definitions =
      Enum.flat_map(tags, fn
        {:{}, _, [tag_module, parser_name, liquid_parser_name]} ->
          tag_definitions(tag_module, parser_name, liquid_parser_name)

        {tag_module, parser_name, liquid_parser_name} ->
          tag_definitions(tag_module, parser_name, liquid_parser_name)
      end)

    quote do
      import NimbleParsec

      # NimbleParsec resolves local parsec(:document) calls to document__0/6.
      # Forward that generated boundary dynamically so recursive tag bodies do
      # not create a static dependency cycle with the complete parser.
      @parser_module Module.concat(["Brando", "Villain", "LiquexParser"])

      unquote_splicing(bridge_definitions)
      unquote_splicing(tag_definitions)
    end
  end

  defp tag_definitions(tag_module, parser_name, liquid_parser_name) do
    parser_definition =
      quote do
        defcombinator(unquote(parser_name), unquote(tag_module).parse())
      end

    liquid_parser_definition =
      if liquid_parser_name do
        quote do
          defcombinator(unquote(liquid_parser_name), unquote(tag_module).parse_liquid_tag())
        end
      end

    [parser_definition, liquid_parser_definition]
    |> Enum.reject(&is_nil/1)
  end
end
