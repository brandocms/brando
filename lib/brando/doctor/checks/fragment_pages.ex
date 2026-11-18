defmodule Brando.Doctor.Checks.FragmentPages do
  @moduledoc """
  Fragments not in the trash whose page is in the trash or gone. A page
  deleted before Brando 0.55 left its fragments on it: the site still renders
  them (templates find a fragment by its parent key, key and language), but
  the admin lists fragments under their page, so nobody saw them. The
  pages listing now shows them under "Fragments without a page", where each
  can be given a page or deleted.

  Fragments that never had a page are counted too, as a note: a fragment
  may be saved with no page, and they are in that list as well.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Doctor.Context
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page

  # The fragments named in the report, per environment: the count says the rest
  @shown 20

  @impl true
  def id, do: "fragment_pages"

  @impl true
  def label, do: dgettext("doctor", "Fragment pages")

  @impl true
  def run(%Context{} = context) do
    context
    |> Context.each_environment(&find/0)
    |> evaluate()
  end

  @doc """
  The live fragments of the current prefix with no page to be listed under:
  `%{orphaned: [{label, reason}], orphaned_count: n, no_page: n}`, where
  `reason` is `:page_trashed` or `:page_missing`.
  """
  def find do
    rows =
      Brando.Repo.all(
        from(f in Fragment,
          left_join: p in Page,
          on: p.id == f.page_id,
          where: is_nil(f.deleted_at) and (is_nil(p.id) or not is_nil(p.deleted_at)),
          order_by: [asc: f.parent_key, asc: f.key, asc: f.language, asc: f.id],
          select: %{
            id: f.id,
            parent_key: f.parent_key,
            key: f.key,
            language: f.language,
            page_id: f.page_id,
            page_deleted: not is_nil(p.deleted_at)
          }
        )
      )

    {no_page, orphaned} = Enum.split_with(rows, &is_nil(&1.page_id))

    %{
      orphaned: orphaned |> Enum.take(@shown) |> Enum.map(&{describe(&1), reason(&1)}),
      orphaned_count: length(orphaned),
      no_page: length(no_page)
    }
  end

  defp describe(row), do: "#{row.parent_key}/#{row.key} [#{row.language}] (id #{row.id}, page #{row.page_id})"

  defp reason(%{page_deleted: true}), do: :page_trashed
  defp reason(_row), do: :page_missing

  @doc "Turns `[{environment_label, found}]` into a result."
  def evaluate(per_environment) do
    orphaned = per_environment |> Enum.map(&elem(&1, 1).orphaned_count) |> Enum.sum()
    no_page = per_environment |> Enum.map(&elem(&1, 1).no_page) |> Enum.sum()

    cond do
      orphaned > 0 ->
        warning(
          dngettext(
            "doctor",
            "%{count} fragment on a page that is in the trash or gone",
            "%{count} fragments on pages that are in the trash or gone",
            orphaned
          ),
          fix:
            dgettext(
              "doctor",
              "the site still shows them, but no page lists them in the admin. Open Pages: they are under Fragments without a page. Edit each one to choose its page, or delete it."
            ),
          items: items(per_environment)
        )

      no_page > 0 ->
        ok(
          dngettext(
            "doctor",
            "every fragment's page is live; %{count} fragment has no page, listed under Fragments without a page",
            "every fragment's page is live; %{count} fragments have no page, listed under Fragments without a page",
            no_page
          )
        )

      true ->
        ok(dgettext("doctor", "every fragment's page is live"))
    end
  end

  defp items(per_environment) do
    for {label, found} <- per_environment, item <- environment_items(found), do: Context.label_item(label, item)
  end

  defp environment_items(%{orphaned: orphaned, orphaned_count: count}) do
    named =
      Enum.map(orphaned, fn
        {fragment, :page_trashed} -> dgettext("doctor", "%{fragment}: the page is in the trash", fragment: fragment)
        {fragment, :page_missing} -> dgettext("doctor", "%{fragment}: the page is gone", fragment: fragment)
      end)

    rest = count - length(orphaned)
    if rest > 0, do: named ++ [dngettext("doctor", "%{count} more", "%{count} more", rest)], else: named
  end
end
