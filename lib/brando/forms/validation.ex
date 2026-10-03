defmodule Brando.Forms.Validation do
  @moduledoc """
  Checks posted values against a form's fields.

  Only the form's own fields are read; anything else in the post is ignored.
  Values are trimmed and capped in length, choices must be one of the field's
  option values, and required fields must be filled in. Messages are the
  site's (`Brando.Forms.Messages`), in the form's language.
  """
  alias Brando.Forms
  alias Brando.Forms.Field

  @email ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
  @max_short 500
  @max_long 10_000

  @doc """
  Returns `{:ok, data}` with the values by field key, or `{:error, errors}`
  with a list of messages by field key.
  """
  @spec validate(Brando.Forms.Form.t(), map()) :: {:ok, map()} | {:error, %{String.t() => [String.t()]}}
  def validate(form, params) when is_map(params) do
    {data, errors} =
      form.fields
      |> Enum.filter(&(&1.type != :section))
      |> Enum.reduce({%{}, %{}}, &collect(&1, params, form.language, &2))

    if errors == %{}, do: {:ok, data}, else: {:error, errors}
  end

  def validate(form, _params), do: validate(form, %{})

  defp collect(field, params, language, {data, errors}) do
    case check(field, Map.get(params, field.key)) do
      {:ok, value} -> {Map.put(data, field.key, value), errors}
      {:error, reason} -> {data, Map.put(errors, field.key, [Forms.message(reason, language)])}
    end
  end

  defp check(%Field{type: type} = field, value) when type in [:checkbox, :consent] do
    checked = value in ["true", "on", true]
    if field.required and not checked, do: {:error, :unticked}, else: {:ok, checked}
  end

  defp check(%Field{type: :checkboxes} = field, value) do
    values = value |> List.wrap() |> Enum.filter(&is_binary/1) |> Enum.reject(&(&1 == ""))

    cond do
      Enum.any?(values, &(&1 not in field.option_values)) -> {:error, :invalid_choice}
      field.required and values == [] -> {:error, :none_chosen}
      true -> {:ok, Enum.filter(field.option_values, &(&1 in values))}
    end
  end

  defp check(field, value) do
    value = if is_binary(value), do: String.trim(value), else: ""

    cond do
      value == "" and field.required -> {:error, :required}
      value == "" -> {:ok, nil}
      String.length(value) > max_length(field) -> {:error, :too_long}
      true -> check_value(field, value)
    end
  end

  defp check_value(%Field{type: :email}, value) do
    if Regex.match?(@email, value), do: {:ok, value}, else: {:error, :invalid_email}
  end

  defp check_value(%Field{type: :number}, value) do
    case Float.parse(value) do
      {_, ""} -> {:ok, value}
      _ -> {:error, :invalid_number}
    end
  end

  defp check_value(%Field{type: :date}, value) do
    case Date.from_iso8601(value) do
      {:ok, _} -> {:ok, value}
      _ -> {:error, :invalid_date}
    end
  end

  defp check_value(%Field{type: type} = field, value) when type in [:select, :radio] do
    if value in field.option_values, do: {:ok, value}, else: {:error, :invalid_choice}
  end

  defp check_value(_field, value), do: {:ok, value}

  defp max_length(%Field{type: :textarea}), do: @max_long
  defp max_length(_), do: @max_short
end
