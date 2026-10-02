defmodule Brando.Forms.Display do
  @moduledoc """
  How a `Brando.Forms.Submission` reads in the admin and its CSV export:
  fields labelled as they were when it was sent, choices by their labels.
  """
  use Gettext, backend: Brando.Gettext

  alias Brando.Forms.Field

  @doc """
  The submission's keys with their labels, in the order of the form in its
  language (`forms` maps language to form); keys the form no longer has last.
  """
  def labels(forms, submission) do
    order =
      case Map.get(forms, submission.language) do
        nil -> []
        form -> form.fields |> Enum.filter(&(&1.type != :section)) |> Enum.map(& &1.key)
      end

    keys = Enum.uniq(Enum.filter(order, &Map.has_key?(submission.data, &1)) ++ Map.keys(submission.data))
    Enum.map(keys, &{&1, Map.get(submission.labels, &1) || &1})
  end

  @doc "A submitted value as text: option labels rather than values, yes or no for a tick."
  def value(forms, submission, key) do
    field = forms |> Map.get(submission.language) |> then(&(&1 && Enum.find(&1.fields, fn f -> f.key == key end)))
    format(Map.get(submission.data, key), field)
  end

  defp format(nil, _field), do: nil
  defp format(true, _field), do: gettext("Yes")
  defp format(false, _field), do: gettext("No")
  defp format(values, field) when is_list(values), do: Enum.map_join(values, ", ", &format(&1, field))

  defp format(value, %Field{} = field) do
    if Field.options?(field), do: field |> Field.options() |> Map.new() |> Map.get(value, value), else: value
  end

  defp format(value, _field), do: to_string(value)
end
