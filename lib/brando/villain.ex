defmodule Villain do
  @doc """
  Parses `json` (in Villain-format).
  Delegates to the module `villain_parser`, configured in the
  otp_app's config.exs.
  Returns HTML.
  """
  def parse(json) do
    {:ok, data} = Poison.decode(json)
    parser_module = Brando.config(:villain_parser)
    html = Enum.reduce(data, [], fn(d, acc) ->
      [apply(parser_module, String.to_atom(d["type"]), [d["data"]])|acc]
    end)
    Enum.reverse(html)
  end
end