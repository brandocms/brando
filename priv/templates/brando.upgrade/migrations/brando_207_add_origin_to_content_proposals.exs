defmodule Brando.Repo.Migrations.Brando207AddOriginToContentProposals do
  use Ecto.Migration

  @moduledoc """
  Where a content proposal came from (`Brando.Content.Proposals.Record`):
  `origin` is `"assistant"` for the admin's Assistant and `"mcp"` for a tool
  connected over MCP, and `client` names that tool when it is known, such as
  "Claude Code". Proposals from outside the admin have no conversation; the
  Assistant lists them under "From connected tools" for review.

  Existing proposals with a conversation came from the Assistant.
  Content proposals live in the `public` schema only.
  """

  def up do
    alter table(:content_proposals, prefix: "public") do
      add :origin, :text
      add :client, :text
    end

    execute "UPDATE public.content_proposals SET origin = 'assistant' WHERE conversation_id IS NOT NULL"
  end

  def down do
    alter table(:content_proposals, prefix: "public") do
      remove :origin
      remove :client
    end
  end
end
