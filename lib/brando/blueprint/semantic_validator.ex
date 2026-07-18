defmodule Brando.Blueprint.SemanticValidator do
  @moduledoc false

  use Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    with :ok <- Brando.Blueprint.Verifier.verify(dsl_state),
         :ok <- Brando.Blueprint.SecondaryVerifier.verify(dsl_state) do
      {:ok, dsl_state}
    end
  end

  @impl true
  def after?(_transformer), do: true
end
