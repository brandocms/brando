defmodule Brando.Assets.CompletedCallback do
  @moduledoc """
  Validates and invokes media completion callbacks.

  Image, file, and video configurations share the same callback contract. A
  callback receives the completed asset and current user. It can be an arity-2
  function or an MFA tuple; MFA runtime arguments come first, followed by the
  configured extra arguments.

  Completion can be delivered by retryable or duplicate asynchronous work, so
  callbacks that perform external side effects should be idempotent.
  """

  @type t(asset) ::
          nil
          | (asset, term() -> term())
          | {module(), atom(), [term()]}

  @doc """
  Validates a completion callback value.
  """
  @spec validate(term()) :: :ok | {:error, String.t()}
  def validate(nil), do: :ok
  def validate(callback) when is_function(callback, 2), do: :ok

  def validate({module, function, extra_args})
      when is_atom(module) and is_atom(function) and is_list(extra_args),
      do: :ok

  def validate(callback) do
    {:error, "expected nil, an arity-2 function, or {module, function, extra_args}, got: #{inspect(callback)}"}
  end

  @doc """
  Invokes the configured completion callback, if present.

  The callback's return value is intentionally ignored; failures must raise so
  the owning upload or processing boundary can apply its retry behavior.
  """
  @spec run(map(), term(), term()) :: :ok
  def run(config, asset, user) when is_map(config) do
    case Map.get(config, :completed_callback) do
      nil ->
        :ok

      callback when is_function(callback, 2) ->
        callback.(asset, user)
        :ok

      {module, function, extra_args}
      when is_atom(module) and is_atom(function) and is_list(extra_args) ->
        apply(module, function, [asset, user | extra_args])
        :ok

      callback ->
        {:error, message} = validate(callback)
        raise ArgumentError, message
    end
  end
end
