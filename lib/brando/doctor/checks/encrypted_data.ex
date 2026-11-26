defmodule Brando.Doctor.Checks.EncryptedData do
  @moduledoc """
  Whether this installation's secret (`Brando.Crypto`) wrote the database,
  by its marker (`Brando.Crypto.Marker`). Reads only.

  - An error when the marker does not decrypt, or when there is no marker
    and `Brando.Crypto.Audit` finds values this secret cannot read: what
    cannot be read is counted. The fix depends on the cause: when this host
    wrote the marker, the installation's secret has changed or is mistyped,
    and putting it back loses nothing; when the database came from another
    host, this environment needs that installation's secret, and the
    clean-up is for when it cannot be had.
  - Skipped before the migration that adds the marker.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Crypto.Audit
  alias Brando.Crypto.Marker

  @impl true
  def id, do: "encrypted_data"

  @impl true
  def label, do: dgettext("doctor", "Encrypted data")

  @impl true
  def run(_context) do
    state = Marker.state()

    case state.key do
      :unknown ->
        skipped(dgettext("doctor", "no encryption marker table: run the migrations"))

      :ours ->
        ok(dgettext("doctor", "written with this installation's secret"))

      key ->
        counts = Audit.run()

        if key == :foreign or Audit.unreadable?(counts),
          do: foreign(state, counts),
          else: ok(dgettext("doctor", "readable with this installation's secret; the marker is written at the next start"))
    end
  end

  defp foreign(state, counts) do
    error(dgettext("doctor", "the database holds values encrypted with another secret"),
      fix: fix(cause(state)),
      link: {"/admin/config/encrypted-data", dgettext("doctor", "Open Encrypted data")},
      items: items(counts)
    )
  end

  @doc """
  Why the database holds what this secret cannot read: `:changed_here` (this
  host wrote the marker), `{:moved, host}` (it came from `host`) or
  `:unknown` (no marker).
  """
  @spec cause(map()) :: :changed_here | {:moved, String.t()} | :unknown
  def cause(%{marker: %Marker{moved_from: from, moved_key: "foreign"}}) when is_binary(from), do: {:moved, from}
  def cause(%{host: :other, marker: %Marker{host: host}}), do: {:moved, host}
  def cause(%{key: :foreign}), do: :changed_here
  def cause(_state), do: :unknown

  @doc "What to do, for `cause/1`."
  @spec fix(:changed_here | {:moved, String.t()} | :unknown) :: String.t()
  def fix(:changed_here) do
    dgettext(
      "doctor",
      "This installation wrote the database, so its encryption secret has changed or is mistyped: put the right one back in BRANDO_ENCRYPTION_SECRET (config/dev.secret.exs in development) and restart, which loses nothing. Forget what it cannot read only when that secret is lost."
    )
  end

  def fix({:moved, host}) do
    dgettext(
      "doctor",
      "The database came from %{host}: give this environment that installation's encryption secret in BRANDO_ENCRYPTION_SECRET (config/dev.secret.exs in development) and restart. When that secret cannot be had, forget what this one cannot read.",
      host: host
    )
  end

  def fix(:unknown) do
    dgettext(
      "doctor",
      "Either this installation's encryption secret changed, or the database came from another installation: put back the secret it was written with, in BRANDO_ENCRYPTION_SECRET (config/dev.secret.exs in development), and restart. When that secret cannot be had, forget what this one cannot read."
    )
  end

  @doc "The counts of `Brando.Crypto.Audit.run/0` as lines, the kinds with none left out."
  @spec items(Audit.counts()) :: [String.t()]
  def items(counts) do
    for kind <- Audit.kinds(), (count = Map.fetch!(counts, kind)) > 0, do: item(kind, count)
  end

  defp item(:users, n),
    do: dngettext("doctor", "%{count} user's two-factor secret", "%{count} users' two-factor secrets", n)

  defp item(:webhooks, n), do: dngettext("doctor", "%{count} webhook's secret", "%{count} webhooks' secrets", n)

  defp item(:notification_routes, n),
    do: dngettext("doctor", "%{count} notification route's URL", "%{count} notification routes' URLs", n)

  defp item(:figma_token, n), do: dngettext("doctor", "%{count} Figma token", "%{count} Figma tokens", n)
  defp item(:figma_app, n), do: dngettext("doctor", "%{count} Figma app", "%{count} Figma apps", n)

  defp item(:figma_connection, n),
    do: dngettext("doctor", "%{count} Figma connection", "%{count} Figma connections", n)

  defp item(:figma_pending, n),
    do: dngettext("doctor", "%{count} Figma connection being made", "%{count} Figma connections being made", n)
end
