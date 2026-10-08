defmodule E2eProject.MCPClient do
  @moduledoc false
  # The E2E MCP client's Client ID Metadata Document. The E2E server cannot
  # fetch an https document from the internet, so Brando.MCP reads this one
  # instead (`config :brando, Brando.MCP, client_metadata_fetcher: …`); any
  # other client_id is unreachable, as an unknown host would be.

  @client_id "https://e2e-client.example/oauth/client.json"

  def client_id, do: @client_id

  def fetch(@client_id) do
    {:ok,
     Jason.encode!(%{
       client_id: @client_id,
       client_name: "E2E Assistant",
       redirect_uris: ["http://127.0.0.1/callback"],
       grant_types: ["authorization_code", "refresh_token"],
       response_types: ["code"],
       token_endpoint_auth_method: "none"
     })}
  end

  def fetch(_client_id), do: {:error, :unreachable}
end
