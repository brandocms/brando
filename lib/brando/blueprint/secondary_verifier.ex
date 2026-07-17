defmodule Brando.Blueprint.SecondaryVerifier do
  @moduledoc false

  use Spark.Dsl.Verifier

  alias Brando.Blueprint.SecondaryVerifier.Datasources
  alias Brando.Blueprint.SecondaryVerifier.Listings
  alias Brando.Blueprint.SecondaryVerifier.Metadata
  alias Brando.Blueprint.SecondaryVerifier.Translations

  @impl true
  def verify(dsl_state) do
    with :ok <- Datasources.verify(dsl_state),
         :ok <- Metadata.verify(dsl_state),
         :ok <- Listings.verify(dsl_state) do
      Translations.verify(dsl_state)
    end
  end
end
