defmodule Brando.Blueprint.TemplateParser do
  @moduledoc """
  Selects the smallest Liquex parser required by a Blueprint template.

  Identifiers and most legacy absolute URLs only use standard Liquid syntax.
  Parsing those templates with Brando's full custom-tag parser unnecessarily
  puts its generated NimbleParsec module on every Blueprint's compile path.
  Templates that contain a Brando tag retain full backwards compatibility and
  explicitly wait for the custom parser when they are compiled.
  """

  alias Brando.Exception.BlueprintError

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

  @doc """
  Parses a Blueprint template and raises a contextual Blueprint error when the
  Liquid syntax is invalid.

  Use this at DSL compile boundaries where carrying a generic `{:error, ...}`
  tuple into a pattern match would hide which configuration failed.
  """
  @spec parse!(String.t(), :absolute_url | :identifier | :template) :: Liquex.document_t()
  def parse!(template, kind \\ :template) when is_binary(template) do
    case parse(template) do
      {:ok, parsed_template} ->
        parsed_template

      {:error, reason, line} ->
        raise BlueprintError,
          message:
            "Invalid Blueprint #{template_label(kind)} template at line #{line}: #{reason}\n\n" <>
              template
    end
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

  defp template_label(:absolute_url), do: "absolute URL"
  defp template_label(:identifier), do: "identifier"
  defp template_label(:template), do: "Liquid"
end
