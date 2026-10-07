defmodule Brando.Doctor.Checks.JSONLD do
  @moduledoc """
  The site identity that every page's JSON-LD graph is built from: an
  identity per language, each with a name and a logo, and a URL for the site
  (the endpoint's).
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context

  @impl true
  def id, do: "json_ld"

  @impl true
  def label, do: dgettext("doctor", "JSON-LD")

  @impl true
  def run(%Context{} = context) do
    url = Brando.Doctor.Checks.Configuration.site_url()

    context
    |> Context.each_environment(fn ->
      {:ok, identities} = Brando.Sites.list_identities(%{preload: [:logo]})
      Enum.map(identities, &%{language: to_string(&1.language), name: &1.name, logo?: not is_nil(&1.logo)})
    end)
    |> evaluate(url)
  end

  @doc """
  Turns `[{environment_label, [%{language, name, logo?}]}]` and the site's
  `url` into a result.
  """
  def evaluate(per_environment, url) do
    problems = Enum.flat_map(per_environment, &environment_problems/1)
    problems = if blank?(url), do: [dgettext("doctor", "no site URL") | problems], else: problems
    fix = dgettext("doctor", "fill in the identity's name and logo")
    link = {BrandoAdmin.Sites.IdentityLive, dgettext("doctor", "Open identity")}

    cond do
      Enum.any?(per_environment, &(elem(&1, 1) == [])) or blank?(url) ->
        error(dgettext("doctor", "identity missing"), fix: fix, link: link, items: problems)

      problems != [] ->
        warning(
          dngettext(
            "doctor",
            "identity incomplete in %{count} language",
            "identity incomplete in %{count} languages",
            length(problems)
          ),
          fix: fix,
          link: link,
          items: problems
        )

      true ->
        ok(dgettext("doctor", "identity complete"), items: [url])
    end
  end

  defp environment_problems({label, []}), do: [Context.label_item(label, dgettext("doctor", "no identity"))]

  defp environment_problems({label, identities}) do
    for identity <- identities,
        missing = missing_fields(identity),
        missing != [] do
      Context.label_item(
        label,
        dgettext("doctor", "%{language}: no %{missing}", language: identity.language, missing: Enum.join(missing, ", "))
      )
    end
  end

  defp missing_fields(identity) do
    Enum.filter(
      [blank?(identity.name) && dgettext("doctor", "name"), !identity.logo? && dgettext("doctor", "logo")],
      & &1
    )
  end

  defp blank?(value), do: value in [nil, ""]
end
