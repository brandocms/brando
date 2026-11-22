defmodule Brando.Migrations.AddFigmaOAuthToMCPSettingsTest do
  use Brando.ConnCase

  import Brando.MigrationTemplates, only: [down: 2, query!: 1, rows: 2, up: 1]

  @file_name "brando_242_add_figma_oauth_to_mcp_settings.exs"
  @columns ~w(figma_app_set_at figma_app_set_by_id figma_client_id figma_client_id_hint figma_client_secret
              figma_oauth_access_token figma_oauth_connected_at figma_oauth_connected_by_id figma_oauth_expires_at
              figma_oauth_handle figma_oauth_needs_reconnect figma_oauth_pending figma_oauth_refresh_token
              figma_oauth_state_hash)

  defp columns do
    "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'mcp_settings' AND column_name = ANY($1) ORDER BY column_name"
    |> rows([@columns])
    |> List.flatten()
  end

  # A site with a pasted token and its expiry keeps them, with no app and no
  # connection, so its tools keep working before anyone connects Figma
  test "adds the Figma app and its OAuth connection to every setting, empty, and rolls back" do
    query!(
      "INSERT INTO public.mcp_settings (enabled, figma_token, figma_token_hint, figma_token_expires_on, inserted_at, updated_at) VALUES (true, 'cipher', 'abcd', '2026-12-01', now(), now())"
    )

    query!("ALTER TABLE public.mcp_settings " <> Enum.map_join(@columns, ", ", &"DROP COLUMN #{&1}"))
    assert columns() == []

    version = up(@file_name)

    assert columns() == @columns

    assert rows(
             "SELECT figma_token, figma_token_hint, figma_token_expires_on, figma_client_id, figma_oauth_connected_at, figma_oauth_needs_reconnect FROM public.mcp_settings",
             []
           ) == [["cipher", "abcd", ~D[2026-12-01], nil, nil, false]]

    down(@file_name, version)

    assert columns() == []

    assert rows("SELECT figma_token_hint, figma_token_expires_on FROM public.mcp_settings", []) == [
             ["abcd", ~D[2026-12-01]]
           ]
  end
end
