defmodule Brando.Datasource do
  @doc """
  List all registered data sources
  """
  def list_datasources do
    {:ok, modules} = :application.get_key(Brando.otp_app(), :modules)

    modules
    |> Enum.filter(&({:__datasource__, 0} in &1.__info__(:functions)))
    |> Enum.map(& &1.__datasource__())
  end
end
