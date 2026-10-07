defmodule Brando.Redacted do
  @moduledoc """
  Holds a secret — a TOTP secret while it is being set up, a passkey
  challenge — so that it does not show when the struct holding it is
  inspected: in a crash report, a LiveView's logged state, or `IO.inspect/1`.
  Read it with `value/1`.
  """

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: term()}

  @doc "Wraps `value`."
  @spec wrap(term()) :: t()
  def wrap(value), do: %__MODULE__{value: value}

  @doc "The wrapped value."
  @spec value(t()) :: term()
  def value(%__MODULE__{value: value}), do: value

  defimpl Inspect do
    def inspect(_redacted, _opts), do: "#Brando.Redacted<**redacted**>"
  end
end
