defmodule Brando.Villain.RenderScope do
  @moduledoc """
  Reuses read-only render inputs for the duration of one synchronous render.

  Nested parser and ref renders share the scope. Nothing survives the outer
  render, including on failure, so normal cache eviction takes effect on the
  next render. Keys include tenant context when a parser switches tenants.
  """

  @key {__MODULE__, :inputs}

  def run(fun) do
    if Process.get(@key) do
      fun.()
    else
      Process.put(@key, %{})

      try do
        fun.()
      after
        Process.delete(@key)
      end
    end
  end

  def fetch(key, load) do
    case Process.get(@key) do
      nil ->
        load.()

      inputs ->
        key = {Brando.Tenant.current_prefix(), Brando.Tenant.current_site_key(), key}

        case Map.fetch(inputs, key) do
          {:ok, value} ->
            value

          :error ->
            value = load.()
            # Loading can itself request other render inputs.
            Process.put(@key, Map.put(Process.get(@key), key, value))
            value
        end
    end
  end
end
