defmodule Brando.Villain.Var do
  defstruct label: nil,
            type: nil,
            value: nil

  defimpl Liquex.Protocol, for: __MODULE__ do
    def render(%{type: "text", value: value}) do
      value
    end

    def render(%{type: "boolean", value: value}) do
      to_string(value)
    end

    def render(%{type: "html", value: value}) do
      value
    end

    def render(%{type: "color", value: value}) do
      value
    end
  end
end
