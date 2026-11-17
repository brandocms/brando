defmodule Brando.Villain.GetEntryStatusTest do
  # A module links to an entry through a link var, and its template loads the
  # entry with `get_entry`. Editors may link to an entry of any status, so a
  # page can be laid out before what it links to is out. The stored render,
  # which the site serves, shows only a published entry, and the pages that
  # link to it render again when it is published, unpublished or deleted.
  # Live preview shows the entry whatever its status (#3547).
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Worker.EntryPublisher

  @card ~S"""
  {% assign e = card.identifier | get_entry %}
  {% if e %}<div class="card" data-status="{{ e.status }}">{{ e.title }}</div>{% else %}<div class="no-card"></div>{% endif %}
  """

  setup do
    user = Factory.insert(:random_user)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{
          code: @card,
          vars: [%{type: :link, key: "card", label: "Card", link_type: :identifier, creator_id: user.id}]
        }),
        :system
      )

    {:ok, user: user, module: module}
  end

  defp at(seconds), do: DateTime.utc_now() |> DateTime.add(seconds) |> DateTime.truncate(:second)

  defp create_target(user, attrs) do
    params =
      Map.merge(
        %{
          title: "Launch",
          uri: "launch-#{System.unique_integer([:positive])}",
          language: "en",
          template: "default.html"
        },
        attrs
      )

    {:ok, page} = Oban.Testing.with_testing_mode(:manual, fn -> Pages.create_page(params, user) end)
    page
  end

  defp identifier(page) do
    {:ok, identifier} = Brando.Content.get_identifier(Page, page)
    identifier
  end

  # A page whose one module block links to `target`
  defp create_linking_page(user, module, target) do
    block =
      %Page.Blocks{
        block: %Brando.Content.Block{
          type: :module,
          source: "Elixir.Brando.Pages.Page.Blocks",
          module_id: module.id,
          uid: Brando.Utils.generate_uid(),
          refs: [],
          vars: [
            %Brando.Content.Var{
              type: :link,
              key: "card",
              label: "Card",
              link_type: :identifier,
              identifier_id: identifier(target).id,
              creator_id: user.id
            }
          ]
        }
      }
      |> Ecto.Changeset.change()
      |> Map.put(:action, :insert)

    changeset =
      %Page{}
      |> Page.changeset(Factory.params_for(:page, %{title: "Projects", uri: "projects-#{System.unique_integer()}"}), user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [block])
      |> Map.put(:action, :insert)

    {:ok, page} = Pages.create_page(changeset, user)
    {:ok, _} = Brando.Content.Blocks.render_entry(Page, page.id)
    page
  end

  # A page whose one module block links to `target` from a table row
  defp create_page_linking_from_row(user, target) do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{
          code: ~S"""
          {% for row in block.table_rows %}{% assign e = row.card.identifier | get_entry %}{% if e %}<div class="card">{{ e.title }}</div>{% else %}<div class="no-card"></div>{% endif %}{% endfor %}
          """
        }),
        :system
      )

    row = %Brando.Content.TableRow{
      sequence: 0,
      vars: [
        %Brando.Content.Var{
          type: :link,
          key: "card",
          label: "Card",
          link_type: :identifier,
          identifier_id: identifier(target).id,
          creator_id: user.id
        }
      ]
    }

    block =
      %Page.Blocks{
        block: %Brando.Content.Block{
          type: :module,
          source: "Elixir.Brando.Pages.Page.Blocks",
          module_id: module.id,
          uid: Brando.Utils.generate_uid(),
          refs: [],
          vars: [],
          table_rows: [row]
        }
      }
      |> Ecto.Changeset.change()
      |> Map.put(:action, :insert)

    changeset =
      %Page{}
      |> Page.changeset(Factory.params_for(:page, %{title: "Rows", uri: "rows-#{System.unique_integer()}"}), user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [block])
      |> Map.put(:action, :insert)

    {:ok, page} = Pages.create_page(changeset, user)
    {:ok, _} = Brando.Content.Blocks.render_entry(Page, page.id)
    page
  end

  defp stored(page), do: Brando.Repo.get(Page, page.id).rendered_blocks

  defp update_target(target, params, user), do: Pages.update_page(target.id, params, user)

  describe "the stored render" do
    test "shows no card for a draft, shows it once published, and hides it again when unpublished", c do
      target = create_target(c.user, %{status: :draft})
      page = create_linking_page(c.user, c.module, target)

      assert stored(page) =~ ~s(class="no-card")
      refute stored(page) =~ ~s(class="card")

      {:ok, _} = update_target(target, %{status: :published}, c.user)
      assert stored(page) =~ ~s(<div class="card" data-status="published">Launch</div>)

      {:ok, _} = update_target(target, %{status: :disabled}, c.user)
      assert stored(page) =~ ~s(class="no-card")

      {:ok, _} = update_target(target, %{status: :published}, c.user)
      assert stored(page) =~ ~s(class="card")

      {:ok, _} = update_target(target, %{status: :draft}, c.user)
      assert stored(page) =~ ~s(class="no-card")
    end

    test "shows no card for a pending entry, and shows it when its publish_at comes", c do
      target = create_target(c.user, %{status: :published, publish_at: at(3600)})
      assert target.status == :pending

      page = create_linking_page(c.user, c.module, target)
      assert stored(page) =~ ~s(class="no-card")

      # The time comes, and the job the publisher queued for it runs
      BrandoIntegration.Repo.update_all(from(p in Page, where: p.id == ^target.id), set: [publish_at: at(-1)])

      assert :ok =
               perform_job(EntryPublisher, %{
                 "schema" => to_string(Page),
                 "id" => target.id,
                 "status" => "published",
                 "user_id" => c.user.id
               })

      assert Brando.Repo.get(Page, target.id).status == :published
      assert stored(page) =~ ~s(<div class="card" data-status="published">Launch</div>)
    end

    test "a publish_at the sweep finds passed publishes the entry and shows the card", c do
      target = create_target(c.user, %{status: :published, publish_at: at(3600)})
      page = create_linking_page(c.user, c.module, target)
      assert stored(page) =~ ~s(class="no-card")

      BrandoIntegration.Repo.update_all(from(p in Page, where: p.id == ^target.id), set: [publish_at: at(-600)])
      Brando.Publisher.sweep()

      assert stored(page) =~ ~s(class="card")
    end

    test "an expiry at unpublish_at hides the card", c do
      target = create_target(c.user, %{status: :published, unpublish_at: at(3600)})
      page = create_linking_page(c.user, c.module, target)
      assert stored(page) =~ ~s(class="card")

      BrandoIntegration.Repo.update_all(from(p in Page, where: p.id == ^target.id), set: [unpublish_at: at(-1)])

      assert :ok =
               perform_job(EntryPublisher, %{
                 "schema" => to_string(Page),
                 "id" => target.id,
                 "status" => "disabled",
                 "user_id" => c.user.id
               })

      assert stored(page) =~ ~s(class="no-card")
    end

    test "a status change from the listing shows and hides the card", c do
      target = create_target(c.user, %{status: :draft})
      page = create_linking_page(c.user, c.module, target)

      {:ok, _} = Brando.Trait.Status.update_status(Page, target.id, :published, c.user)
      assert stored(page) =~ ~s(class="card")

      {:ok, _} = Brando.Trait.Status.update_status(Page, target.id, :disabled, c.user)
      assert stored(page) =~ ~s(class="no-card")
    end

    test "deleting the entry hides the card", c do
      target = create_target(c.user, %{status: :published})
      page = create_linking_page(c.user, c.module, target)
      assert stored(page) =~ ~s(class="card")

      {:ok, _} = Pages.delete_page(target.id, c.user)
      assert Brando.Repo.get(Page, target.id).deleted_at

      assert stored(page) =~ ~s(class="no-card")
    end
  end

  describe "a link in a table row" do
    test "shows the card once the entry is published, and hides it when unpublished", c do
      target = create_target(c.user, %{status: :draft})
      page = create_page_linking_from_row(c.user, target)
      assert stored(page) =~ ~s(class="no-card")

      {:ok, _} = update_target(target, %{status: :published}, c.user)
      assert stored(page) =~ ~s(<div class="card">Launch</div>)

      {:ok, _} = update_target(target, %{status: :disabled}, c.user)
      assert stored(page) =~ ~s(class="no-card")
    end

    test "hides the card when the entry is deleted", c do
      target = create_target(c.user, %{status: :published})
      page = create_page_linking_from_row(c.user, target)
      assert stored(page) =~ ~s(class="card")

      {:ok, _} = Pages.delete_page(target.id, c.user)
      assert stored(page) =~ ~s(class="no-card")
    end
  end

  describe "the Markdown export" do
    # Served from the site, like the stored render, also to an admin in
    # frontend edit mode
    test "shows only a published entry, in frontend edit mode too", c do
      target = create_target(c.user, %{status: :draft})
      page = create_linking_page(c.user, c.module, target)

      markdown = fn ->
        {:ok, entry} = Brando.Query.get_entry(Page, page.id)
        Brando.FrontendEdit.with_active(fn -> Brando.Villain.Markdown.render(entry.entry_blocks, entry) end)
      end

      refute markdown.() =~ "Launch"

      {:ok, _} = update_target(target, %{status: :published}, c.user)
      assert markdown.() =~ "Launch"
    end
  end

  describe "live preview" do
    test "a full render and a block patch show the draft, with its status for the template", c do
      target = create_target(c.user, %{status: :draft})
      page = create_linking_page(c.user, c.module, target)
      assert stored(page) =~ ~s(class="no-card")

      {:ok, entry} = Brando.Query.get_entry(Page, page.id)
      cache_key = "get-entry-#{System.unique_integer([:positive])}"
      on_exit(fn -> Brando.LivePreview.cleanup_cache(cache_key) end)

      html = Brando.LivePreview.render(Page, entry, cache_key, target: :blocks)
      assert html =~ ~s(<div class="card" data-status="draft">Launch</div>)

      [%{block: block}] = entry.entry_blocks
      assert Brando.Villain.render_block(block, entry, annotate_blocks: true) =~ ~s(data-status="draft")
      assert Brando.Villain.render_block(block, entry) =~ ~s(class="no-card")
    end
  end
end
