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

  @asset_types ~w(image file video gallery)

  @doc """
  Serialize a config target into the canonical string stored on assets and
  passed through upload contracts.

  Form inputs commonly use tuples internally so they can retain the schema
  module and field atom. Browser/provider boundaries must not guess how to
  stringify those tuples: a provider video created with the wrong target is
  subsequently invisible to the originating picker and loses its field-level
  configuration.
  """
  def serialize(nil), do: nil
  def serialize(target) when is_binary(target), do: target

  def serialize({type, schema, field}) do
    type = asset_type!(type)
    schema = schema_name!(schema)
    field = segment!(field, :field)
    "#{type}:#{schema}:#{field}"
  end

  def serialize({type, schema, :function, function}) do
    type = asset_type!(type)
    schema = schema_name!(schema)
    function = segment!(function, :function)
    "#{type}:#{schema}:function:#{function}"
  end

  def serialize(%{config_target: target}), do: serialize(target)

  def serialize(target) do
    raise ArgumentError, "invalid config_target #{inspect(target)}"
  end

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
        raise ArgumentError,
              "invalid config_target field #{inspect(field_name)} for #{inspect(schema)}"
    end
  end

  defp existing_atom(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> :error
  end

  defp asset_type!(type) when is_atom(type), do: asset_type!(Atom.to_string(type))

  defp asset_type!(type) when type in @asset_types, do: type

  defp asset_type!(type) do
    raise ArgumentError, "invalid config_target asset type #{inspect(type)}"
  end

  defp schema_name!(schema) when is_atom(schema) do
    if Code.ensure_loaded?(schema) and Brando.Blueprint.blueprint?(schema) do
      inspect(schema)
    else
      raise ArgumentError,
            "invalid config_target schema #{inspect(schema)} — must be a loaded Brando blueprint module"
    end
  end

  defp schema_name!(schema) when is_binary(schema) do
    schema_module!(schema) |> inspect()
  end

  defp schema_name!(schema) do
    raise ArgumentError, "invalid config_target schema #{inspect(schema)}"
  end

  defp segment!(segment, _kind) when is_atom(segment), do: Atom.to_string(segment)

  defp segment!(segment, _kind) when is_binary(segment) and segment != "", do: segment

  defp segment!(segment, kind) do
    raise ArgumentError, "invalid config_target #{kind} #{inspect(segment)}"
  end
end
