defmodule Brando.Blueprint.Authorization do
  @moduledoc false

  def validate!(options, caller) do
    options = Macro.expand(options, caller)
    unless Keyword.keyword?(options), do: raise(ArgumentError, "authorization expects keyword options")

    Enum.map(options, fn {key, value} ->
      value = Macro.expand(value, caller)
      validate_option!(key, value)
      {key, value}
    end)
  end

  defp validate_option!(:key, value) do
    unless is_binary(value) and Regex.match?(~r/^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$/, value),
      do: raise(ArgumentError, "authorization key must be a stable lowercase name such as my_app.projects")
  end

  defp validate_option!(:section, value) do
    unless is_binary(value) and String.trim(value) != "",
      do: raise(ArgumentError, "authorization section must be a non-empty display name")
  end

  defp validate_option!(:actions, value) do
    unless is_list(value) and Enum.all?(value, &(is_atom(&1) and &1 not in [nil, true, false])),
      do: raise(ArgumentError, "authorization actions must be a literal list of atoms, for example [:approve]")
  end

  defp validate_option!(:policy, value) do
    unless is_atom(value) and value not in [nil, true, false],
      do: raise(ArgumentError, "authorization policy must be a module implementing authorize/3 and scope/3")
  end

  defp validate_option!(key, _), do: raise(ArgumentError, "unknown authorization option #{inspect(key)}")
end
