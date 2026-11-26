defmodule Brando.Doctor.Checks.EncryptionSecret do
  @moduledoc """
  Whether `Brando.Crypto` has a secret of its own
  (`config :brando, Brando.Crypto, secret: …`). It encrypts two-factor
  secrets, webhook and notification route secrets and the other values Brando
  keeps in the database, and keys the hashes of recovery codes and passkey
  handles. A site's environments share one secret, so a database copied
  between them stays readable (see the deployment guide).

  - A warning when none is configured: Brando then uses the endpoint's
    `secret_key_base`, which differs per environment and cannot be rotated
    without losing what it encrypted.
  - An error when the configured one is unusable: not a string of at least 32
    bytes, or the installer's placeholder that was never filled in. Two-factor
    sign-in fails then.
  - A warning when it is the same value as the endpoint's `secret_key_base`:
    the value developers keep is then the key production signs sessions with.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  @impl true
  def id, do: "encryption_secret"

  @impl true
  def label, do: dgettext("doctor", "Encryption secret")

  @impl true
  def run(_context), do: evaluate(Brando.config(Brando.Crypto)[:secret], secret_key_base())

  @doc "The result for the configured `secret` (nil when none is) and the endpoint's `secret_key_base`."
  @spec evaluate(term(), term()) :: Brando.Doctor.Result.t()
  def evaluate(secret, secret_key_base) do
    cond do
      is_nil(secret) and usable?(secret_key_base) ->
        warning(dgettext("doctor", "none of its own: encrypted values use the endpoint's secret_key_base"),
          fix:
            dgettext(
              "doctor",
              "set BRANDO_ENCRYPTION_SECRET on the servers, and config/dev.secret.exs in development, to one value for the whole site: on a site in production, production's current SECRET_KEY_BASE. See the deployment guide"
            )
        )

      is_binary(secret) and String.starts_with?(secret, "__BRANDO_") ->
        error(dgettext("doctor", "still the installer's placeholder: two-factor sign-in fails"),
          fix:
            dgettext(
              "doctor",
              "run mix brando.install again: it fills in the secret in .envrc.prod, .envrc.staging and config/dev.secret.exs"
            )
        )

      not usable?(secret || secret_key_base) ->
        error(dgettext("doctor", "no secret of at least 32 bytes: two-factor sign-in fails"),
          fix: dgettext("doctor", "set config :brando, Brando.Crypto, secret: to the site's encryption secret")
        )

      secret == secret_key_base ->
        warning(dgettext("doctor", "the same value as the endpoint's secret_key_base"),
          fix:
            dgettext(
              "doctor",
              "give the endpoint a new SECRET_KEY_BASE and deploy: everyone is signed out once, and encrypted values stay readable"
            )
        )

      true ->
        ok(dgettext("doctor", "a secret of its own"))
    end
  end

  defp usable?(secret), do: is_binary(secret) and byte_size(secret) >= 32

  # The endpoint's config table is not there until it starts
  defp secret_key_base do
    Brando.endpoint().config(:secret_key_base)
  rescue
    ArgumentError -> Application.get_env(Brando.otp_app(), Brando.endpoint(), [])[:secret_key_base]
  end
end
