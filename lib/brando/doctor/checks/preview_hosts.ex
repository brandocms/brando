defmodule Brando.Doctor.Checks.PreviewHosts do
  @moduledoc """
  The static sites' preview host pattern (`Brando.SSG.PreviewHost`):

    * a value that is no string, a pattern of the wrong form, or one an
      installation host matches, is an error, as it is at boot;
    * a pattern with `tenancy_mode` other than `:multi` has no effect, which
      the check says;
    * an active static site with no preview host (a key longer than a DNS
      label, a host longer than 253 bytes, or a host an environment binds,
      named with the site that binds it), a session cookie whose `Domain`
      covers the pattern's base, and, with the served hosts file on
      (`Brando.Tenant.ServedHosts`), a preview host its DNS check does not
      admit, are warnings.

  The session options are the ones the endpoint's sockets carry, as a
  generated endpoint shares its `@session_options` with `Plug.Session`.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.SSG.PreviewHost
  alias Brando.Tenant.ServedHosts

  @impl true
  def id, do: "preview_hosts"

  @impl true
  def label, do: dgettext("doctor", "Preview hosts")

  @impl true
  def run(_context) do
    cond do
      not PreviewHost.set?() ->
        skipped(dgettext("doctor", "no preview_host set"))

      Brando.Tenant.mode() != :multi ->
        skipped(
          dgettext("doctor", "preview_host has no effect with tenancy_mode %{mode}", mode: inspect(Brando.Tenant.mode()))
        )

      true ->
        check(PreviewHost.problems())
    end
  end

  defp check([]), do: evaluate(PreviewHost.unserved_sites(), session_domains(), not_admitted())

  defp check(problems) do
    error(Enum.map_join(problems, ", ", &problem/1),
      fix:
        dgettext(
          "doctor",
          "set preview_host to {site_key} followed by a host name no installation host is directly under, such as {site_key}.preview.example.com"
        )
    )
  end

  defp problem(:not_a_string), do: dgettext("doctor", "preview_host is no string")
  defp problem(:placeholder), do: dgettext("doctor", "preview_host does not name {site_key} once, as its first label")
  defp problem(:base), do: dgettext("doctor", "preview_host has no host name of two labels after {site_key}.")

  defp problem({:installation_host, host}),
    do: dgettext("doctor", "the installation's host %{host} matches preview_host", host: host)

  @doc """
  The result for the sites with no preview host (`Brando.SSG.PreviewHost.unserved_sites/0`),
  the session cookie domains, and the preview hosts the served hosts file
  does not admit, each with its state.
  """
  def evaluate(unserved, session_domains, not_admitted) do
    base = PreviewHost.base_host()
    covering = Enum.filter(session_domains, &covers?(&1, base))

    findings =
      Enum.map(unserved, &unserved/1) ++
        Enum.map(covering, &cookie/1) ++ Enum.map(not_admitted, &not_admitted(&1, PreviewHost.wildcard()))

    case findings do
      [] ->
        ok(dgettext("doctor", "a preview host per static site under %{base}", base: base), items: PreviewHost.hosts())

      findings ->
        summaries = findings |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.join(", ")
        fixes = findings |> Enum.map(&elem(&1, 2)) |> Enum.uniq() |> Enum.join("; ")
        warning(summaries, fix: fixes, items: Enum.map(findings, &elem(&1, 1)))
    end
  end

  defp unserved({site, :key_too_long}) do
    {dgettext("doctor", "site key too long for a preview host"),
     dgettext("doctor", "%{site}: its key is longer than a DNS label (63 bytes)", site: site.key),
     dgettext("doctor", "a site with a shorter key gets a preview host")}
  end

  defp unserved({site, :host_too_long}) do
    {dgettext("doctor", "preview host too long"),
     dgettext("doctor", "%{site}: its preview host is longer than 253 bytes", site: site.key),
     dgettext("doctor", "choose a shorter preview_host base")}
  end

  defp unserved({site, {:bound, owner}}) do
    {dgettext("doctor", "preview host bound to an environment"),
     dgettext("doctor", "%{site}: its preview host is an environment's domain or redirect host of %{owner}",
       site: site.key,
       owner: owner.key
     ), dgettext("doctor", "remove the host from that environment to give the site its preview host")}
  end

  defp cookie(domain) do
    {dgettext("doctor", "session cookie sent to preview hosts"),
     dgettext("doctor", "the session cookie's domain %{domain} covers the preview hosts", domain: domain),
     dgettext(
       "doctor",
       "choose a preview_host base no session cookie's domain covers, or drop the domain option: a build's scripts run on its preview host"
     )}
  end

  defp not_admitted({host, state}, wildcard) do
    {dgettext("doctor", "preview hosts not admitted"), "#{host}: #{inspect(state)}",
     dgettext("doctor", "point the wildcard DNS record %{record} at this installation", record: wildcard)}
  end

  # A cookie for `example.com` is sent to every host under it
  defp covers?(domain, base) do
    domain = domain |> String.trim() |> String.downcase() |> String.trim_leading(".")
    domain != "" and (base == domain or String.ends_with?(base, "." <> domain))
  end

  defp session_domains do
    for {_path, _module, opts} <- Brando.endpoint().__sockets__(),
        transport <- [:websocket, :longpoll],
        config = opts[transport],
        is_list(config),
        connect_info = config[:connect_info],
        is_list(connect_info),
        session = Keyword.get(Enum.filter(connect_info, &is_tuple/1), :session),
        is_list(session),
        domain = session[:domain],
        is_binary(domain),
        uniq: true,
        do: domain
  rescue
    _no_endpoint -> []
  end

  # A host waiting for its DNS, not resolving, or whose lookup failed
  defp not_admitted do
    if ServedHosts.enabled?() do
      hosts = ServedHosts.status().hosts

      for host <- PreviewHost.hosts(),
          state = hosts[host],
          state not in [nil, :served, :not_written, :checking],
          do: {host, state}
    else
      []
    end
  end
end
