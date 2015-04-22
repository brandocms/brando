defmodule Villain do
  @moduledoc """
  Villain is our JS editor.
  https://github.com/twined/villain
  """

  @doc """
  Parses `json` (in Villain-format).
  Delegates to the module `villain_parser`, configured in the
  otp_app's config.exs.
  Returns HTML.
  """
  @spec parse(String.t) :: String.t
  def parse(""), do: ""
  def parse(nil), do: ""
  def parse(json) when is_binary(json) do
    {:ok, data} = Poison.decode(json)
    do_parse(data)
  end
  def parse(json) when is_list(json) do
    do_parse(json)
  end
  defp do_parse(data) do
    parser_module = Brando.config(Villain)[:parser]
    html = Enum.reduce(data, [], fn(d, acc) ->
      [apply(parser_module, String.to_atom(d["type"]), [d["data"]])|acc]
    end)
    html |> Enum.reverse |> Enum.join
  end
end