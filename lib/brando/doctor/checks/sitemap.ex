defmodule Brando.Doctor.Checks.Sitemap do
  @moduledoc """
  The sitemap: the application has a sitemap module, and its index
  (`sitemaps/sitemap.xml.gz` under the media path) has been generated within
  the last two days. Brando regenerates it every night.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context

  @stale_after_hours 48

  @impl true
  def id, do: "sitemap"

  @impl true
  def label, do: dgettext("doctor", "Sitemap")

  @impl true
  def run(%Context{} = context), do: run(context, Brando.Sitemap.exists?())

  @doc "Runs the check, given whether the application has a sitemap module."
  def run(%Context{} = context, sitemap_module?) do
    if sitemap_module? do
      context
      |> Context.each_environment(&generated_at/0)
      |> evaluate(context.now)
    else
      warning(dgettext("doctor", "no sitemap module"), fix: dgettext("doctor", "run mix brando.gen.sitemap"))
    end
  end

  @doc "When the sitemap index of the current environment was written, or nil."
  def generated_at do
    path = Path.join([Brando.Tenant.Storage.current_media_root(), "sitemaps", "sitemap.xml.gz"])

    case File.stat(path, time: :posix) do
      {:ok, stat} -> DateTime.from_unix!(stat.mtime)
      {:error, _} -> nil
    end
  end

  @doc "Turns `[{environment_label, generated_at | nil}]` into a result, measured from `now`."
  def evaluate(per_environment, now) do
    missing = for {label, nil} <- per_environment, do: label
    generated = for {label, %DateTime{} = at} <- per_environment, do: {label, at}
    stale = Enum.filter(generated, fn {_label, at} -> DateTime.diff(now, at, :hour) >= @stale_after_hours end)

    items =
      Enum.map(per_environment, fn
        {label, nil} -> Context.label_item(label, dgettext("doctor", "not generated"))
        {label, at} -> Context.label_item(label, dgettext("doctor", "generated %{at}", at: format(at)))
      end)

    fix = dgettext("doctor", "Utilities → Generate sitemap")
    link = {"#utils-sitemap", dgettext("doctor", "Generate sitemap")}

    cond do
      missing != [] ->
        error(dgettext("doctor", "not generated"), fix: fix, link: link, items: items)

      stale != [] ->
        {_label, oldest} = Enum.min_by(stale, &elem(&1, 1), DateTime)

        warning(dgettext("doctor", "last generated %{age} ago", age: age(now, oldest)),
          fix: dgettext("doctor", "check that the nightly SitemapGenerator job runs, or Utilities → Generate sitemap"),
          link: link,
          items: items
        )

      true ->
        {_label, oldest} = Enum.min_by(generated, &elem(&1, 1), DateTime)
        ok(dgettext("doctor", "generated %{age} ago", age: age(now, oldest)), items: items)
    end
  end

  defp format(at), do: at |> DateTime.truncate(:second) |> DateTime.to_string()

  defp age(now, at) do
    hours = max(DateTime.diff(now, at, :hour), 0)

    cond do
      hours < 1 -> dgettext("doctor", "less than an hour")
      hours < 48 -> dngettext("doctor", "%{count} hour", "%{count} hours", hours)
      true -> dngettext("doctor", "%{count} day", "%{count} days", div(hours, 24))
    end
  end
end
