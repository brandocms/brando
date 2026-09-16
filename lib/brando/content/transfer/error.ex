defmodule Brando.Content.Transfer.Error do
  @moduledoc false
  defexception [:message]

  def fail!(message), do: raise(__MODULE__, message: message)

  def protect(fun) do
    {:ok, fun.()}
  rescue
    error in [__MODULE__, Brando.Content.Definition.Error] -> {:error, error.message}
    _ in Ecto.StaleEntryError -> {:error, "Content changed during import. Review a new preview."}
    _ in Ecto.ConstraintError -> {:error, "A database constraint rejected the import. No content was committed."}
    error in Ecto.InvalidChangesetError -> {:error, "Content validation failed: #{inspect(error.changeset.errors)}"}
    _ in File.Error -> {:error, "Media storage could not complete the operation. Check storage availability and retry."}
  end
end
