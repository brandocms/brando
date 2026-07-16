defmodule Brando.Blueprint.SemanticValidator do
  @moduledoc false

  use Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    case Brando.Blueprint.Verifier.verify(dsl_state) do
      :ok -> {:ok, dsl_state}
      {:error, error} -> {:error, error}
    end
  end

  @impl true
  def after?(_transformer), do: true
end
