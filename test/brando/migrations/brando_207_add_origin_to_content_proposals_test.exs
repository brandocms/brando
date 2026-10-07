defmodule Brando.Migrations.Brando207AddOriginToContentProposalsTest do
  # Runs the upgrade template inside the sandbox transaction against a
  # content_proposals table rolled back to before it; Postgres DDL is
  # transactional, so everything is undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  alias BrandoIntegration.Repo

  @template Application.app_dir(
              :brando,
              "priv/templates/brando.upgrade/migrations/brando_207_add_origin_to_content_proposals.exs"
            )

  defp rows(sql, params), do: Repo.query!(sql, params).rows

  defp run_template do
    [{module, _bytecode}] = Code.compile_file(@template)

    try do
      Ecto.Migrator.up(Repo, System.unique_integer([:positive]), module, log: false, migration_lock: false)
    after
      :code.purge(module)
      :code.delete(module)
    end
  end

  defp insert(conversation_id) do
    id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO public.content_proposals
        (id, conversation_id, version, scope, operations, fingerprints, module_versions, problems, effects,
         expires_at, inserted_at, updated_at)
      VALUES ($1, $2, 1, 'public', '{}', '{}', '{}', '{}', '{}', now(), now(), now())
      """,
      [Ecto.UUID.dump!(id), conversation_id && Ecto.UUID.dump!(conversation_id)]
    )

    id
  end

  test "adds origin and client; proposals with a conversation came from the Assistant" do
    Repo.query!("ALTER TABLE public.content_proposals DROP COLUMN origin, DROP COLUMN client")
    in_conversation = insert(Ecto.UUID.generate())
    outside = insert(nil)

    run_template()

    origin = fn id ->
      rows("SELECT origin, client FROM public.content_proposals WHERE id = $1", [Ecto.UUID.dump!(id)])
    end

    assert origin.(in_conversation) == [["assistant", nil]]
    assert origin.(outside) == [[nil, nil]]
  end
end
