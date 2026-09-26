defmodule Brando.Repo.Migrations.Brando186AddAiConversationTarget do
  use Ecto.Migration

  @moduledoc """
  The entry and block field a content assistant conversation was opened for
  from the block editor.
  """

  def change do
    alter table(:ai_conversations, prefix: "public") do
      add :target, :map
    end
  end
end
