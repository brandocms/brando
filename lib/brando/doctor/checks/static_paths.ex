defmodule Brando.Doctor.Checks.StaticPaths do
  @moduledoc """
  With a site served from its published build (the deploy strategy `:local`,
  `Brando.SSG.LocalDelivery`), the web module's `static_paths/0` is the same
  list as the `only:` of the endpoint's `Plug.Static`.

  On a host serving a build, a file the build lacks reaches the release's
  `Plug.Static` when its first path segment is in `static_paths/0`
  (`Brando.Plug.SiteAssets.static_file?/1`). A prefix only `only:` names is
  answered with the build's 404 page; one only `static_paths/0` names gets the
  404 page too, after a trip through the endpoint. The check reads the
  endpoint's source as `Brando.Doctor.Checks.Robots` does, so it compares the
  lists where that source is, as in development. A release has no source and
  keeps no record of the options a plug was compiled with (its beams are
  stripped of debug info), so there the check is skipped, saying it runs in
  development, but still warns when the web module has no `static_paths/0`.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Checks.Robots
  alias Brando.Sites.Site

  @impl true
  def id, do: "static_paths"

  @impl true
  def label, do: dgettext("doctor", "Static paths of served builds")

  @impl true
  def run(_context) do
    if Brando.Tenant.enabled?() and Enum.any?(Brando.Tenant.Registry.list_sites(), &Site.local_delivery?/1) do
      {source, _file} = Robots.endpoint_source()
      only = if source, do: Robots.static_only(source), else: :no_source
      evaluate(only, static_paths())
    else
      skipped(dgettext("doctor", "no site is served by this installation"))
    end
  end

  @doc """
  Turns the endpoint's `only:` (`Brando.Doctor.Checks.Robots.static_only/1`,
  or `:no_source` without the endpoint's source) and the web module's
  `static_paths/0` (nil without one) into a result.
  """
  def evaluate(only, static_paths)

  def evaluate(_only, nil) do
    warning(dgettext("doctor", "the web module has no static_paths/0"),
      fix:
        dgettext(
          "doctor",
          "define static_paths/0 in the web module with the endpoint's Plug.Static only: list, and pass it as only:"
        )
    )
  end

  def evaluate(:no_source, _static_paths) do
    skipped(
      dgettext(
        "doctor",
        "runs where the endpoint's source can be read, as in development: a release has no source to read Plug.Static's only: from"
      )
    )
  end

  def evaluate(:unknown, _static_paths),
    do: skipped(dgettext("doctor", "the endpoint's Plug.Static only: could not be read"))

  def evaluate({:call, _module, entries}, static_paths), do: compare(entries, static_paths)
  def evaluate({:literal, entries}, static_paths), do: compare(entries, static_paths)

  def evaluate(:none, _static_paths) do
    warning(dgettext("doctor", "the endpoint's Plug.Static has no only:"),
      fix: dgettext("doctor", "pass the web module's static_paths/0 as the endpoint's Plug.Static only:")
    )
  end

  defp compare(entries, static_paths) do
    only_endpoint = entries -- static_paths
    only_web = static_paths -- entries

    if only_endpoint == [] and only_web == [] do
      ok(dgettext("doctor", "static_paths/0 matches the endpoint's Plug.Static only:"))
    else
      warning(dgettext("doctor", "static_paths/0 and the endpoint's Plug.Static only: differ"),
        fix: dgettext("doctor", "pass the web module's static_paths/0 as the endpoint's Plug.Static only:"),
        items:
          Enum.map(
            only_endpoint,
            &dgettext(
              "doctor",
              "%{entry}: in the endpoint's only: but not in static_paths/0, its files answer the build's 404 page",
              entry: &1
            )
          ) ++
            Enum.map(
              only_web,
              &dgettext("doctor", "%{entry}: in static_paths/0 but not in the endpoint's only:", entry: &1)
            )
      )
    end
  end

  defp static_paths do
    web_module = Brando.config(:web_module)

    if is_atom(web_module) and Code.ensure_loaded?(web_module) and function_exported?(web_module, :static_paths, 0),
      do: Enum.map(web_module.static_paths(), &to_string/1)
  end
end
