defmodule Brando.Type.UserConfig do
  @moduledoc """
  Defines a type for a user configuration field.

  ### Options
  """

  use Ecto.Type

  @type t :: %__MODULE__{}
  @derive Jason.Encoder

  defstruct show_onboarding: false

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :map

  @doc """
  Cast should return OUR type no matter what the input.
  """
  def cast(val) when is_binary(val) do
    val = Poison.decode!(val, as: %Brando.Type.UserConfig{})
    {:ok, val}
  end

  def cast(val) when is_map(val), do: {:ok, val}

  @doc """
  Return empty struct
  """
  def blank?(_), do: %Brando.Type.UserConfig{}

  @doc """
  Load from database. We receive it as a map since Postgrex does the conversion.
  """
  def load(data) when is_map(data) do
    require Logger
    Logger.error(inspect(data, pretty: true))

    data =
      for {key, val} <- data do
        {String.to_existing_atom(key), val}
      end
      |> Enum.into(%{})

    {:ok, struct!(__MODULE__, data)}
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(val) when is_map(val), do: {:ok, val}
end
