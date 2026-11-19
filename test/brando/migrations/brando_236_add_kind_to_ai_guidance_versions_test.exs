defmodule Brando.Migrations.AddKindToAiGuidanceVersionsTest do
  use Brando.ConnCase

  import Brando.MigrationTemplates, only: [down: 2, query!: 1, rows: 2, up: 1]

  @file_name "brando_236_add_kind_to_ai_guidance_versions.exs"

  defp kind_column?,
    do:
      rows(
        "SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ai_guidance_versions' AND column_name = 'kind'",
        []
      ) != []

  defp indexes,
    do:
      rows(
        "SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'ai_guidance_versions' AND indexname LIKE '%scope%' ORDER BY indexname",
        []
      )

  # Guidance from before the kind is the assistant's
  test "marks existing guidance as the assistant's, indexes by kind, and rolls back" do
    query!("DROP INDEX public.ai_guidance_versions_scope_kind_inserted_at_index")
    query!("ALTER TABLE public.ai_guidance_versions DROP COLUMN kind")

    query!(
      "CREATE INDEX ai_guidance_versions_scope_inserted_at_index ON public.ai_guidance_versions (scope, inserted_at)"
    )

    query!(
      "INSERT INTO public.ai_guidance_versions (id, scope, text, inserted_at) VALUES (gen_random_uuid(), 'here', 'Use the lede', now())"
    )

    version = up(@file_name)

    assert rows("SELECT kind, text FROM public.ai_guidance_versions", []) == [["assistant", "Use the lede"]]
    assert indexes() == [["ai_guidance_versions_scope_kind_inserted_at_index"]]

    query!(
      "INSERT INTO public.ai_guidance_versions (id, scope, kind, text, inserted_at) VALUES (gen_random_uuid(), 'here', 'figma', 'Skip the footer', now())"
    )

    down(@file_name, version)

    refute kind_column?()
    assert rows("SELECT text FROM public.ai_guidance_versions", []) == [["Use the lede"]]
    assert indexes() == [["ai_guidance_versions_scope_inserted_at_index"]]
  end
end
