defmodule Brando.Migrations.AddFigmaTokenToMCPSettingsTest do
  use Brando.ConnCase

  import Brando.MigrationTemplates, only: [down: 2, query!: 1, rows: 2, up: 1]

  @file_name "brando_232_add_figma_token_to_mcp_settings.exs"

  defp columns,
    do:
      rows(
        "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'mcp_settings' AND column_name LIKE 'figma%' ORDER BY column_name",
        []
      )

  # A switch from before the token keeps its row, with no token
  test "adds the Figma token columns to every switch, and rolls back" do
    query!("INSERT INTO public.mcp_settings (enabled, inserted_at, updated_at) VALUES (true, now(), now())")

    query!(
      "ALTER TABLE public.mcp_settings DROP COLUMN figma_token, DROP COLUMN figma_token_hint, " <>
        "DROP COLUMN figma_token_set_at, DROP COLUMN figma_token_set_by_id"
    )

    version = up(@file_name)

    assert columns() == [["figma_token"], ["figma_token_hint"], ["figma_token_set_at"], ["figma_token_set_by_id"]]
    assert rows("SELECT enabled, figma_token FROM public.mcp_settings", []) == [[true, nil]]

    down(@file_name, version)

    assert columns() == []
    assert rows("SELECT enabled FROM public.mcp_settings", []) == [[true]]
  end
end
