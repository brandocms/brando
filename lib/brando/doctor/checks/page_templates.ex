defmodule Brando.Doctor.Checks.PageTemplates do
  @moduledoc """
  With `tenancy_mode: :multi` and a non-empty `config :brando, site_frontends`:
  in each environment, the pages whose `template` is not a function of the
  site's `PageHTML` (`Brando.Pages.list_templates/0`), which fail to render.
  An environment whose site has no frontend is left to
  `Brando.Doctor.Checks.SiteFrontends`.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Doctor.Context
  alias Brando.Pages.Page
  alias Brando.Tenant

  @impl true
  def id, do: "page_templates"

  @impl true
  def label, do: dgettext("doctor", "Pages without their template")

  @impl true
  def run(%Context{} = context) do
    frontends = Brando.config(:site_frontends) || %{}

    if Tenant.mode() == :multi and is_map(frontends) and map_size(frontends) > 0,
      do: context |> Context.each_environment(&missing/0) |> evaluate(),
      else: skipped(dgettext("doctor", "only with tenancy_mode :multi and site_frontends"))
  end

  @doc """
  The current environment's pages whose template its site's `PageHTML` has
  no function for, as `%{template => count}`; `nil` for a site without a
  frontend.
  """
  @spec missing() :: %{String.t() => pos_integer()} | nil
  def missing do
    case Brando.Site.Frontend.page_html() do
      nil ->
        nil

      _page_html ->
        {:ok, templates} = Brando.Pages.list_templates()

        from(p in Page,
          where: is_nil(p.deleted_at) and p.template not in ^templates,
          group_by: p.template,
          select: {p.template, count()}
        )
        |> Brando.Repo.all()
        |> Map.new()
    end
  end

  @doc "Turns `[{environment_label, %{template => count} | nil}]` into a result."
  def evaluate(per_environment) do
    counted = for {label, %{} = missing} <- per_environment, map_size(missing) > 0, do: {label, missing}

    case counted |> Enum.flat_map(fn {_, missing} -> Map.values(missing) end) |> Enum.sum() do
      0 ->
        ok(dgettext("doctor", "every page's template is in its site's PageHTML"))

      total ->
        warning(
          dngettext(
            "doctor",
            "%{count} page whose template its site's PageHTML lacks",
            "%{count} pages whose template their site's PageHTML lacks",
            total
          ),
          fix:
            dgettext(
              "doctor",
              "they fail to render: add the template to the site's PageHTML, or choose another for the page"
            ),
          items:
            for {label, missing} <- counted do
              count = missing |> Map.values() |> Enum.sum()
              templates = missing |> Map.keys() |> Enum.sort() |> Enum.join(", ")

              Context.label_item(
                label,
                dngettext("doctor", "%{count} page (%{templates})", "%{count} pages (%{templates})", count,
                  templates: templates
                )
              )
            end
        )
    end
  end
end
