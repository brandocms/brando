defmodule Brando.Doctor.Source.Lock do
  @moduledoc false
  # Reads one dependency's entry from the contents of a mix.lock.
  #
  # Mix evaluates the lock (`Code.eval_quoted/3`). This only parses it and
  # walks the result, accepting literals (atoms, strings, numbers, lists and
  # tuples), so a lock that holds anything else is not run, just ignored.

  @doc """
  The entry for `app` in `contents`, a mix.lock, or `nil`:

      iex> Brando.Doctor.Source.Lock.entry(~s(%{"brando": {:git, "https://x/brando.git", "12c2289", [branch: "main"]}}), :brando)
      {:git, "https://x/brando.git", "12c2289", [branch: "main"]}
  """
  @spec entry(String.t(), atom()) :: tuple() | nil
  def entry(contents, app) do
    with {:ok, {:%{}, _meta, pairs}} <- Code.string_to_quoted(contents, emit_warnings: false),
         {^app, quoted} <- List.keyfind(pairs, app, 0),
         {:ok, entry} when is_tuple(entry) <- literal(quoted) do
      entry
    else
      _ -> nil
    end
  end

  defp literal({:{}, _meta, elements}), do: literals(elements, &List.to_tuple/1)
  defp literal({first, second}), do: literals([first, second], &List.to_tuple/1)
  defp literal(list) when is_list(list), do: literals(list, & &1)
  defp literal(term) when is_atom(term) or is_binary(term) or is_number(term), do: {:ok, term}
  defp literal(_quoted), do: :error

  defp literals(quoted, build) do
    quoted
    |> Enum.reduce_while([], fn element, acc ->
      case literal(element) do
        {:ok, value} -> {:cont, [value | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      values -> {:ok, build.(Enum.reverse(values))}
    end
  end
end
