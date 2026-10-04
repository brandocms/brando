defmodule BrandoAdmin.Sites.BlockAuditLive do
  @moduledoc """
  Utilities → Loose blocks: the block trees no entry links to, what was
  checked about each, and removing the ones nothing can bring back
  (`Brando.Content.BlockAudit`). Removed trees go to an archive they can be
  restored from.
  """
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  import Ecto.Query

  alias Brando.Content.BlockAudit
  alias Brando.Content.Usage
  alias Brando.Images.Image
  alias BrandoAdmin.Components.Content

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  @thumbs 3

  def mount(_params, %{"user_token" => token}, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign(:current_user, Brando.Users.get_user_by_session_token(token))
       |> set_admin_locale()
       |> assign(:selected, MapSet.new())
       |> assign_audit()}
    else
      {:ok, assign(socket, :socket_connected, false)}
    end
  end

  def handle_params(params, url, socket) do
    {:noreply, socket |> assign(:params, params) |> assign(:uri, URI.parse(url))}
  end

  # The tree's first images that still exist; a tree without any shows its
  # module's sketch instead.
  defp thumbs(tree, images) do
    for id <- Enum.take(tree.image_ids, @thumbs), image = images[id], do: image
  end

  defp assign_audit(socket) do
    scan = BlockAudit.scan()
    image_ids = scan.trees |> Enum.flat_map(&Enum.take(&1.image_ids, @thumbs)) |> Enum.uniq()
    images = Map.new(Brando.Repo.all(from i in Image, where: i.id in ^image_ids), &{&1.id, &1})

    holders =
      scan.trees
      |> Enum.flat_map(& &1.held_by)
      |> Enum.map(&holder_key/1)
      |> Enum.uniq()
      |> Usage.labels()

    removable = for tree <- scan.trees, tree.status == :removable, into: MapSet.new(), do: tree.id

    socket
    |> assign(:scan, scan)
    |> assign(:groups, Enum.group_by(scan.trees, & &1.source) |> Enum.sort())
    |> assign(:images, images)
    |> assign(:holders, holders)
    |> assign(:removable, removable)
    |> assign(:selected, MapSet.intersection(socket.assigns.selected, removable))
    |> assign(:archive, BlockAudit.list_archive())
  end

  defp holder_key(%{entry_type: type, entry_id: id}), do: {Module.concat([type]), id}

  def handle_event("toggle", %{"id" => id}, socket) do
    id = String.to_integer(id)

    selected =
      cond do
        not MapSet.member?(socket.assigns.removable, id) -> socket.assigns.selected
        MapSet.member?(socket.assigns.selected, id) -> MapSet.delete(socket.assigns.selected, id)
        true -> MapSet.put(socket.assigns.selected, id)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("select_all", _, socket), do: {:noreply, assign(socket, :selected, socket.assigns.removable)}
  def handle_event("select_none", _, socket), do: {:noreply, assign(socket, :selected, MapSet.new())}

  def handle_event("remove", _, socket) do
    case BlockAudit.remove(MapSet.to_list(socket.assigns.selected), socket.assigns.current_user) do
      {:ok, %{removed: removed, blocks: blocks, skipped: skipped}} ->
        message =
          ngettext(
            "Removed %{count} loose block tree (%{blocks} blocks). It is in the archive below.",
            "Removed %{count} loose block trees (%{blocks} blocks). They are in the archive below.",
            removed,
            count: removed,
            blocks: blocks
          )

        message =
          if skipped == [],
            do: message,
            else:
              message <>
                " " <>
                ngettext(
                  "%{count} was left: it is in use again.",
                  "%{count} were left: they are in use again.",
                  length(skipped),
                  count: length(skipped)
                )

        send(self(), {:toast, message})
        {:noreply, socket |> assign(:selected, MapSet.new()) |> assign_audit()}

      {:error, reason} ->
        send(self(), {:toast, gettext("Nothing was removed: %{reason}", reason: inspect(reason))})
        {:noreply, assign_audit(socket)}
    end
  end

  def handle_event("restore", %{"id" => id}, socket) do
    case BlockAudit.restore(String.to_integer(id)) do
      {:ok, _root_id} ->
        send(self(), {:toast, gettext("The blocks are back, as loose as they were.")})

      {:error, reason} ->
        send(self(), {:toast, gettext("Could not restore: %{reason}", reason: to_string_reason(reason))})
    end

    {:noreply, assign_audit(socket)}
  end

  defp to_string_reason(reason) when is_binary(reason), do: reason
  defp to_string_reason(reason), do: inspect(reason)

  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <div class="utils-workspace block-audit">
      <header class="utils-page-heading">
        <div>
          <.link navigate={Brando.routes().admin_live_path(@socket, BrandoAdmin.Sites.UtilsLive)} class="utils-eyebrow">
            ← {gettext("Utilities")}
          </.link>
          <h1>{gettext("Loose blocks")}</h1>
          <p>
            {gettext(
              "Blocks no entry links to any more. A block removed from an entry is kept so that an older version of the entry can be restored with it; once no version holds it, nothing can bring it back, and it only keeps its images looking used."
            )}
          </p>
        </div>
      </header>

      <dl class="utils-report-stats block-audit-stats">
        <div>
          <dd>{@scan.totals.loose_trees}</dd>
          <dt>
            {ngettext("loose block tree", "loose block trees", @scan.totals.loose_trees)} · {ngettext(
              "%{count} block",
              "%{count} blocks",
              @scan.totals.loose_blocks,
              count: @scan.totals.loose_blocks
            )}
          </dt>
        </div>
        <div>
          <dd>{@scan.totals.removable}</dd>
          <dt>{gettext("can be removed")}</dt>
        </div>
        <div class={[@scan.totals.held > 0 && "needs-review"]}>
          <dd>{@scan.totals.held}</dd>
          <dt>{gettext("still held")}</dt>
        </div>
        <div>
          <dd>{@scan.totals.blocks}</dd>
          <dt>{gettext("blocks in all")}</dt>
        </div>
      </dl>

      <section class="block-audit-checked" aria-labelledby="block-audit-checked-title">
        <h2 id="block-audit-checked-title">{gettext("What was checked")}</h2>
        <ul>
          <li>
            <strong>{gettext("Links")}</strong>
            <div>
              {gettext("No row in any table that points at blocks names a block of the tree:")}
              <span class="block-audit-tables">
                <code :for={table <- @scan.checked.link_tables}>{table}</code>
              </span>
            </div>
          </li>
          <li>
            <strong>{gettext("Versions")}</strong>
            <div>
              {ngettext(
                "%{count} stored version was read; none of them may hold a block of the tree.",
                "%{count} stored versions were read; none of them may hold a block of the tree.",
                @scan.checked.revisions,
                count: @scan.checked.revisions
              )}
              <span :if={@scan.checked.undecodable_revisions > 0} class="block-audit-warning">
                {ngettext(
                  "%{count} version could not be read, so nothing can be removed.",
                  "%{count} versions could not be read, so nothing can be removed.",
                  @scan.checked.undecodable_revisions,
                  count: @scan.checked.undecodable_revisions
                )}
              </span>
            </div>
          </li>
          <li>
            <strong>{gettext("Recovery copies")}</strong>
            <div>
              {ngettext(
                "%{count} recovery copy was searched for the tree's blocks.",
                "%{count} recovery copies were searched for the tree's blocks.",
                @scan.checked.drafts,
                count: @scan.checked.drafts
              )}
            </div>
          </li>
        </ul>
      </section>

      <p :if={@scan.trees == []} class="block-audit-empty">{gettext("No loose blocks.")}</p>

      <section :if={@scan.trees != []} class="block-audit-list">
        <div class="block-audit-toolbar">
          <span>
            {gettext("%{count} selected", count: MapSet.size(@selected))}
          </span>
          <button type="button" class="utils-button" phx-click="select_all" disabled={MapSet.size(@removable) == 0}>
            {gettext("Select all that can be removed")}
          </button>
          <button type="button" class="utils-button quiet" phx-click="select_none" disabled={MapSet.size(@selected) == 0}>
            {gettext("Select none")}
          </button>
          <button
            type="button"
            class="utils-button block-audit-remove"
            phx-click="remove"
            disabled={MapSet.size(@selected) == 0}
            data-confirm-destructive
            data-confirm={
              ngettext(
                "Remove %{count} loose block tree? It goes to the archive and can be restored from there.",
                "Remove %{count} loose block trees? They go to the archive and can be restored from there.",
                MapSet.size(@selected),
                count: MapSet.size(@selected)
              )
            }
          >
            <.icon name="trash" />{gettext("Remove selected")}
          </button>
        </div>

        <div :for={{source, trees} <- @groups} class="block-audit-group">
          <h3>
            {source}
            <span>{ngettext("%{count} tree", "%{count} trees", length(trees), count: length(trees))}</span>
          </h3>
          <ul>
            <li :for={tree <- trees} class={["block-audit-tree", "is-#{tree.status}"]}>
              <label class="block-audit-check">
                <input
                  type="checkbox"
                  checked={MapSet.member?(@selected, tree.id)}
                  disabled={tree.status != :removable}
                  phx-click="toggle"
                  phx-value-id={tree.id}
                  aria-label={gettext("Select block %{id}", id: tree.id)}
                />
              </label>
              <div class="block-audit-thumbs">
                <Content.image :for={image <- thumbs(tree, @images)} image={image} size={:smallest} />
                <img
                  :if={thumbs(tree, @images) == [] && tree.module_svg}
                  class="block-audit-sketch"
                  src={"data:image/svg+xml;base64,#{tree.module_svg}"}
                  alt=""
                />
              </div>
              <div class="block-audit-what">
                <strong>{tree.module || gettext("Block")}</strong>
                <span :if={tree.description not in [nil, ""]} class="block-audit-description">{tree.description}</span>
                <span :if={tree.excerpt} class="block-audit-excerpt">{tree.excerpt}</span>
                <small>
                  #{tree.id} · {ngettext("%{count} block", "%{count} blocks", length(tree.block_ids),
                    count: length(tree.block_ids)
                  )}
                  <span :if={tree.inserted_at}>· {BrandoAdmin.Dates.short(tree.inserted_at)}</span>
                </small>
              </div>
              <div class="block-audit-status">
                <span :if={tree.status == :removable} class="block-audit-chip is-ok">{gettext("Can be removed")}</span>
                <span :if={tree.status == :held_by_draft} class="block-audit-chip">{gettext("In a recovery copy")}</span>
                <span :if={tree.status == :unverifiable} class="block-audit-chip">{gettext("Cannot be verified")}</span>
                <div :if={tree.status == :held_by_revision} class="block-audit-held">
                  <span class="block-audit-chip">{gettext("Held by a version")}</span>
                  <span :for={holder <- Enum.take(tree.held_by, 3)}>
                    <.link :if={@holders[holder_key(holder)][:url]} navigate={@holders[holder_key(holder)].url}>
                      {@holders[holder_key(holder)].label}
                    </.link>
                    <span :if={!@holders[holder_key(holder)][:url]}>{@holders[holder_key(holder)][:label]}</span>
                    · {gettext("version %{number}", number: holder.revision)}
                  </span>
                </div>
              </div>
            </li>
          </ul>
        </div>
      </section>

      <section :if={@archive != []} class="block-audit-archive" aria-labelledby="block-audit-archive-title">
        <div class="utils-section-heading">
          <h2 id="block-audit-archive-title">{gettext("Archive")}</h2>
          <p>{gettext("Removed block trees, kept as they were. Restoring one puts it back as a loose block.")}</p>
        </div>
        <ul>
          <li :for={item <- @archive}>
            <div class="block-audit-what">
              <strong>{item.summary["module"] || gettext("Block")}</strong>
              <span :if={item.summary["description"] not in [nil, ""]} class="block-audit-description">
                {item.summary["description"]}
              </span>
              <span :if={item.summary["excerpt"]} class="block-audit-excerpt">{item.summary["excerpt"]}</span>
              <small>
                #{item.root_block_id} · {item.summary["source"]} · {ngettext(
                  "%{count} block",
                  "%{count} blocks",
                  item.block_count,
                  count: item.block_count
                )} · {gettext("removed %{date}", date: BrandoAdmin.Dates.short(item.inserted_at))}
              </small>
            </div>
            <button type="button" class="utils-button" phx-click="restore" phx-value-id={item.id}>
              {gettext("Restore")}
            </button>
          </li>
        </ul>
      </section>
    </div>
    """
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language |> to_string() |> Gettext.put_locale()
    socket
  end
end
