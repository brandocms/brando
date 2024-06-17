defmodule Brando.Repo.Migrations.AddURLtoIdentifier do
  use Ecto.Migration
  import Ecto.Query

  def up do
    alter table(:content_identifiers) do
      add :url, :text
    end

    # go through all content identifiers and set URL
    query = from i in "content_identifiers",
      select: i

    identifiers = Brando.repo().all(query)

    require Logger
    Logger.error """

    identifiers:
    #{inspect(identifiers, pretty: true)}

    """

    raise "hepp"

    # Enum.each(identifiers, fn identifier ->
    #   url = "/#{identifier.schema}/#{identifier.id}"
    #   Brando.repo().update!(identifier, %{url: url})
    # end)
  end

  def down do
    alter table(:content_identifiers) do
      remove :url
    end
  end
end
