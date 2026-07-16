defmodule Brando.Blueprint.TemplateParser do
  @moduledoc """
  Selects the smallest Liquex parser required by a Blueprint template.

  Identifiers and most legacy absolute URLs only use standard Liquid syntax.
  Parsing those templates with Brando's full custom-tag parser unnecessarily
  puts its generated NimbleParsec module on every Blueprint's compile path.
  Templates that contain a Brando tag retain full backwards compatibility and
  explicitly wait for the custom parser when they are compiled.
  """

  @custom_tag_pattern ~r/{%-?\s*(?:
    datasource|enddatasource|endhide|fragment|headless_ref|hide|inspect|link|
    picture|ref|route_i18n|route|t|video
  )\b/x

  @doc """
  Parses a Blueprint Liquid template with the smallest compatible parser.
  """
  @spec parse(String.t()) :: {:ok, Liquex.document_t()} | {:error, String.t(), pos_integer()}
  def parse(template) when is_binary(template) do
    parser = parser_for(template)
    Code.ensure_compiled!(parser)
    Liquex.parse(template, parser)
  end

  @doc false
  @spec parser_for(String.t()) :: module()
  def parser_for(template) when is_binary(template) do
    if Regex.match?(@custom_tag_pattern, template) do
      Module.concat(["Brando", "Villain", "LiquexParser"])
    else
      Liquex.Parser.Base
    end
  end
end
