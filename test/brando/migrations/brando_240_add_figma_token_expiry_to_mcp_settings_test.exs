defmodule Brando.Migrations.AddFigmaTokenExpiryToMCPSettingsTest do
  use Brando.ConnCase

  import Brando.MigrationTemplates, only: [down: 2, query!: 1, rows: 2, up: 1]

  @file_name "brando_240_add_figma_token_expiry_to_mcp_settings.exs"

  defp columns,
    do:
      rows(
        "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'mcp_settings' AND column_name = 'figma_token_expires_on'",
        []
      )

  # A token saved before keeps its row, with no expiry recorded
  test "adds the Figma token's expiry date to every setting, empty, and rolls back" do
    query!(
      "INSERT INTO public.mcp_settings (enabled, figma_token_hint, inserted_at, updated_at) VALUES (true, 'abcd', now(), now())"
    )

    query!("ALTER TABLE public.mcp_settings DROP COLUMN figma_token_expires_on")

    version = up(@file_name)

    assert columns() == [["figma_token_expires_on"]]
    assert rows("SELECT figma_token_hint, figma_token_expires_on FROM public.mcp_settings", []) == [["abcd", nil]]

    down(@file_name, version)

    assert columns() == []
    assert rows("SELECT figma_token_hint FROM public.mcp_settings", []) == [["abcd"]]
  end
end
