defmodule Brando.TranslationFixtures do
  @moduledoc false

  alias Brando.Content.Block
  alias Brando.Repo
  alias Brando.SyncTest.Article

  @doc "Inserts a module block with a single `body` text ref into `article`'s blocks at `sequence`."
  def add_block(article, module, user, text, sequence) do
    params = %{
      "uid" => Brando.Utils.generate_uid(),
      "type" => "module",
      "module_id" => module.id,
      "creator_id" => user.id,
      "source" => to_string(Article.Blocks),
      "refs" => [
        %{
          "uid" => Brando.Utils.generate_uid(),
          "name" => "body",
          "data" => %{"type" => "text", "data" => %{"text" => text}}
        }
      ]
    }

    block = %Block{} |> Block.recursive_block_changeset(params, user) |> Repo.insert!()
    struct(Article.Blocks, %{entry_id: article.id, block_id: block.id, sequence: sequence}) |> Repo.insert!()
    block
  end
end
