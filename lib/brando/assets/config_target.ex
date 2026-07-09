defmodule Brando.Assets.ConfigTarget do
  @moduledoc """
  Strict resolution of `config_target` string segments.

  Targets like `"file:MyApp.Schema:field"` or
  `"image:MyApp.Schema:function:fn_name"` arrive from clients (upload-manager
  intake, form component events) and from editor-authored module/var
  definitions, so resolution must never mint atoms or call arbitrary code:

  - schema segments resolve through *existing* atoms only, and the module must
    be a Brando blueprint
  - `function` targets only call functions the blueprint actually exports with
    arity 0
  - field segments resolve through existing atoms only (blueprint fields exist
    as atoms at compile time)

  Resolution failures raise `ArgumentError` with a descriptive message —
  upload-manager callers rescue and fall back to the default config
  (`Brando.Uploads.resolve_*_config/1`); pipeline callers surface the raise.
  """

  @doc """
  Resolve a schema segment to an existing, loaded blueprint module.

  Accepts both `"MyApp.Schema"` and `"Elixir.MyApp.Schema"` forms. Returns
  `{:ok, module}` or `:error`.
  """
  def schema_module(schema) when is_binary(schema) do
    module = String.to_existing_atom("Elixir." <> String.trim_leading(schema, "Elixir."))

    if Code.ensure_loaded?(module) and Brando.Blueprint.blueprint?(module) do
      {:ok, module}
    else
      :error
    end
  rescue
    ArgumentError -> :error
  end

  @doc """
  Same as `schema_module/1` but raises `ArgumentError` on failure.
  """
  def schema_module!(schema) do
    case schema_module(schema) do
      {:ok, module} ->
        module

      :error ->
        raise ArgumentError,
              "invalid config_target schema #{inspect(schema)} — must be an existing Brando blueprint module"
    end
  end

  @doc """
  Call a zero-arity config function on a blueprint schema — the
  `"<type>:<schema>:function:<fn>"` target form. Raises `ArgumentError` unless
  the schema is a blueprint exporting `fn/0`.
  """
  def config_function!(schema, fn_string) do
    module = schema_module!(schema)

    with {:ok, fun} <- existing_atom(fn_string),
         true <- function_exported?(module, fun, 0) do
      apply(module, fun, [])
    else
      _ ->
        raise ArgumentError,
              "invalid config_target function #{inspect(fn_string)} on #{inspect(schema)} — " <>
                "the blueprint must export #{fn_string}/0"
    end
  end

  @doc """
  Resolve a field segment to an existing atom. Raises `ArgumentError` for
  atoms that don't exist (never mints).
  """
  def field_atom!(schema, field_name) do
    case existing_atom(field_name) do
      {:ok, atom} ->
        atom

      :error ->
        raise ArgumentError, "invalid config_target field #{inspect(field_name)} for #{inspect(schema)}"
    end
  end

  defp existing_atom(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> :error
  end
end
