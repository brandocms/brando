defmodule Brando.Type.Role do
  @moduledoc """
  Defines a type for managing roles in user models.
  """

  @behaviour Ecto.Type

  @default_role_cfg roles: %{staff: 1, admin: 2, superuser: 4}

  use Bitwise, only_operators: true

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :integer

  @doc """
  Cast should return OUR type no matter what the input.
  In this case, `list` will be a list of binaries from a form.
  Ex: ["1", "2", "4"]
  """
  def cast(list) when is_list(list) do
    set_roles = Keyword.get(get_config, :roles)
    # first turn the list of binaries into a sum
    roles = Enum.reduce(list, 0, fn (role, acc) ->
      cond do
        is_binary(role)  -> acc + String.to_integer(role)
        is_integer(role) -> acc + role
        is_atom(role)    -> acc + set_roles[role]
      end
    end)

    {:ok, reduce_roles(set_roles, roles)}
  end

  @doc """
  Only triggered by our default "0" value
  """
  def cast(binary) when is_binary(binary) do
    {:ok, String.to_integer(binary)}
  end

  @doc """
  Nil returns empty list
  """
  def cast(nil) do
    {:ok, []}
  end

  @doc """
  Cast anything else is a failure
  """
  def cast(_), do: :error

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: false

  @doc """
  When loading `roles` from the database, we are guaranteed to
  receive an integer (as database are stricts) and we will
  just return it to be stored in the model struct.
  """
  def load(roles) when is_integer(roles) do
    set_roles = Keyword.get(get_config(), :roles)

    {:ok, reduce_roles(set_roles, roles)}
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(integer) when is_integer(integer), do: {:ok, integer}
  def dump(string) when is_binary(string), do: {:ok, String.to_integer(string)}
  def dump(list) when is_list(list) do
    set_roles = Keyword.get(get_config(), :roles)
    acc = cond do
      is_atom(List.first(list))    ->
        Enum.reduce(list, 0, &(&2 + set_roles[&1]))
      is_binary(List.first(list))  ->
        Enum.reduce(list, 0, &(&2 + String.to_integer(&1)))
      is_integer(List.first(list)) ->
        Enum.reduce(list, 0, &(&2 + &1))
    end
    {:ok, acc}
  end
  def dump(nil), do: {:ok, 0}
  def dump(_), do: :error

  defp reduce_roles(set_roles, roles) do
    Enum.reduce(set_roles, [], fn ({role_k, role_v}, acc) ->
      (roles &&& role_v) == role_v && [role_k|acc] || acc
    end)
  end

  defp get_config do
    Application.get_env(:brando, Brando.Type.Role) || @default_role_cfg
  end
end
