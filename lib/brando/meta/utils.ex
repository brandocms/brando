defmodule Brando.Meta.Utils do
  @moduledoc """

  """

  @doc """
  Convert locale to a format OG understands
  """
  @spec encode_locale(binary) :: binary
  def encode_locale("en"), do: "en_us"
  def encode_locale("no"), do: "nb_no"
  def encode_locale("nb"), do: "nb_no"
  def encode_locale("nn"), do: "nn_no"
  def encode_locale(locale), do: locale
end
