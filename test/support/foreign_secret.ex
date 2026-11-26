defmodule Brando.Test.ForeignSecret do
  @moduledoc """
  Values as another installation's secret encrypted them, for tests of
  `Brando.Crypto.Audit` and `Brando.Crypto.Marker`: what `Brando.Crypto`
  writes, under a key this installation does not have.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.MCP.Setting
  alias Brando.Notifications.Route
  alias Brando.Repo
  alias Brando.Users.RecoveryCode
  alias Brando.Users.Security
  alias Brando.Webhooks.Webhook
  alias Plug.Crypto.KeyGenerator
  alias Plug.Crypto.MessageEncryptor

  @other "another installation's encryption secret, 32+ bytes"

  @doc "`plaintext` encrypted for `context` with another secret."
  def encrypt(plaintext, context) do
    MessageEncryptor.encrypt(plaintext, context, KeyGenerator.generate(@other, "brando encrypted value", length: 32), "")
  end

  defp encrypt(true, plaintext, context), do: Brando.Crypto.encrypt(plaintext, context)
  defp encrypt(false, plaintext, context), do: encrypt(plaintext, context)

  @doc "Turns two-factor authentication on for `user`, with a secret readable here or not, and two recovery codes."
  def two_factor!(%{id: user_id}, readable?) do
    ciphertext = encrypt(readable?, "JBSWY3DPEHPK3PXP", "users.totp_secret:#{user_id}")
    now = DateTime.utc_now()

    Repo.insert!(%Security{user_id: user_id, totp_secret: ciphertext, totp_enabled_at: DateTime.truncate(now, :second)},
      on_conflict: [set: [totp_secret: ciphertext, totp_enabled_at: DateTime.truncate(now, :second)]],
      conflict_target: :user_id
    )

    for _ <- 1..2 do
      Repo.insert!(%RecoveryCode{
        user_id: user_id,
        hashed_code: :crypto.strong_rand_bytes(32),
        inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      })
    end

    ciphertext
  end

  @doc "A webhook in `prefix` (nil for `public`) with a secret readable here or not."
  def webhook!(prefix, readable?, attrs \\ []) do
    webhook =
      Repo.insert!(
        struct(
          %Webhook{name: "Hook", url: "https://hooks.example.com/", secret_ciphertext: "", secret_hint: "abcd"},
          attrs
        ),
        prefix: prefix || "public"
      )

    ciphertext = encrypt(readable?, "whsec_secret", "webhooks.secret:#{webhook.id}")

    Repo.update_all(from(w in Webhook, where: w.id == ^webhook.id), [set: [secret_ciphertext: ciphertext]],
      prefix: prefix || "public"
    )

    %{webhook | secret_ciphertext: ciphertext}
  end

  @doc "A notification route in `prefix` (nil for `public`): Slack or Teams with a URL readable here or not, or email."
  def route!(prefix, kind, readable?, attrs \\ []) do
    route =
      Repo.insert!(
        struct(%Route{name: "Route #{kind}", kind: kind, events: ["mention"], recipient_ids: [1]}, attrs),
        prefix: prefix || "public"
      )

    if kind == :email do
      route
    else
      ciphertext = encrypt(readable?, "https://hooks.slack.com/services/x", "notifications.url:#{route.id}")

      Repo.update_all(from(r in Route, where: r.id == ^route.id), [set: [url_ciphertext: ciphertext]],
        prefix: prefix || "public"
      )

      %{route | url_ciphertext: ciphertext}
    end
  end

  @doc """
  The installation's MCP settings row (no site), with a pasted token, an
  OAuth app, a connection and a connection being made, each readable here or
  not as `readable` says (`%{token: true, app: false, …}`; left out: absent).
  """
  def figma_setting!(readable) do
    fields =
      [
        token: [figma_token: "token"],
        app: [figma_client_id: "client_id", figma_client_secret: "client_secret"],
        connection: [figma_oauth_access_token: "access_token", figma_oauth_refresh_token: "refresh_token"],
        pending: [figma_oauth_pending: "pending"]
      ]
      |> Enum.filter(fn {group, _} -> Map.has_key?(readable, group) end)
      |> Enum.flat_map(fn {group, columns} ->
        Enum.map(columns, fn {column, field} ->
          {column, encrypt(Map.fetch!(readable, group), "value", "mcp.figma_#{field}:0:0")}
        end)
      end)

    connected = if Map.has_key?(readable, :connection), do: [figma_oauth_connected_at: DateTime.utc_now()], else: []
    Repo.insert!(struct(%Setting{site_id: nil, environment_id: nil}, fields ++ connected))
  end
end
