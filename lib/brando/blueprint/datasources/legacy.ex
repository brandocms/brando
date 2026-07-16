defmodule Brando.Blueprint.Datasources.Legacy do
  @moduledoc false

  @deprecated "list/2 outside of datasource/1 is deprecated. Wrap inside datasource/1"
  defmacro list(_, {_, _, [{_, _, [[_, _], _]}]}, _) do
    raise "datasource :list callbacks with 2 arity is deprecated. use `fn module, language, vars -> ... end` instead"
  end

  @deprecated "list/2 outside of datasource/1 is deprecated. Wrap inside datasource/1"
  defmacro list(_key, _fun), do: nil

  @deprecated "single/2 outside of datasource/1 is deprecated. Wrap inside datasource/1"
  defmacro single(_key, _fun), do: nil

  defmacro selection(_, {_, _, [{_, _, [[_, _], _]}]}, _) do
    raise "datasource :selection LIST callbacks with 2 arity is deprecated. use `fn module, language, vars -> ... end` instead"
  end

  defmacro selection(_, _, {_, _, [{_, _, [[_, _], _]}]}) do
    raise "datasource :selection GET callbacks with 2 arity (module, ids) is deprecated. use `fn identifiers -> ... end` instead"
  end

  @deprecated "selection/3 outside of datasource/1 is deprecated. Wrap inside datasource/1"
  defmacro selection(_key, _list_fun, _get_fun), do: nil
end
