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
    {:ok, user: user, module: create_module(user, @card)}
  end

  defp create_module(user, code) do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{
          code: code,
          vars: [%{type: :link, key: "card", label: "Card", link_type: :identifier, creator_id: user.id}]
        }),
        :system
      )

    module
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

  # A page whose one module block links to the page itself, such as a "this
  # project" card
  defp create_self_linking_page(user, module, attrs) do
    page = create_target(user, attrs)

    block =
      Brando.Repo.insert!(%Brando.Content.Block{
        type: :module,
        source: "Elixir.Brando.Pages.Page.Blocks",
        module_id: module.id,
        uid: Brando.Utils.generate_uid(),
        creator_id: user.id,
        vars: [
          %Brando.Content.Var{
            type: :link,
            key: "card",
            label: "Card",
            link_type: :identifier,
            identifier_id: identifier(page).id,
            creator_id: user.id
          }
        ]
      })

    Brando.Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
    {:ok, _} = Brando.Content.Blocks.render_entry(Page, page.id)
    page
  end

  # What the form's save does: render the blocks with the entry as the form
  # has it, before the save, and save the rendered changeset
  defp save_from_form(page, params, user) do
    {:ok, entry} = Brando.Query.get_entry(Page, page.id)
    save_from_form_opened_as(entry, params, user)
  end

  # The form keeps the entry it loaded when it opened
  defp save_from_form_opened_as(entry, params, user) do
    entry
    |> Page.changeset(params, user)
    |> then(&BrandoAdmin.Components.Form.render_blocks_for_save([{:blocks, Page.Blocks, nil, []}], &1))
    |> Pages.update_page(user)
  end

  # The entries the cascades `fun` queues render, run by hand
  defp rendered_by_cascade(fun) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      fun.()

      for %{args: args} <- all_enqueued(worker: Brando.Worker.EntryCascade),
          do: :ok = perform_job(Brando.Worker.EntryCascade, args)

      for %{args: %{"entry_id" => id}} <- all_enqueued(worker: Brando.Worker.EntryRenderer), do: id
    end)
  end

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

  describe "an entry whose own blocks link to it" do
    test "a publish from the form shows the card, rendered once, and an unpublish hides it", c do
      target = create_self_linking_page(c.user, c.module, %{status: :draft})
      assert stored(target) =~ ~s(class="no-card")

      # The form renders the blocks before it saves, with the status it saves
      rendered = rendered_by_cascade(fn -> {:ok, _} = save_from_form(target, %{status: :published}, c.user) end)
      assert stored(target) =~ ~s(<div class="card" data-status="published">Launch</div>)
      refute target.id in rendered

      {:ok, _} = save_from_form(target, %{status: :disabled}, c.user)
      assert stored(target) =~ ~s(class="no-card")
    end

    test "clearing the publish_at of a pending entry in the form publishes it and shows the card", c do
      target = create_self_linking_page(c.user, c.module, %{status: :published, publish_at: at(3600)})
      assert Brando.Repo.get(Page, target.id).status == :pending

      {:ok, _} = save_from_form(target, %{publish_at: nil}, c.user)

      assert Brando.Repo.get(Page, target.id).status == :published
      assert stored(target) =~ ~s(<div class="card" data-status="published">Launch</div>)
    end

    test "a publish_at that passes while the form renders publishes the entry and shows the card", c do
      target = create_self_linking_page(c.user, c.module, %{status: :draft})
      {:ok, entry} = Brando.Query.get_entry(Page, target.id)

      # Rendered while the date is ahead, saved once it has passed
      entry
      |> Page.changeset(%{status: :published, publish_at: at(3600)}, c.user)
      |> then(&BrandoAdmin.Components.Form.render_blocks_for_save([{:blocks, Page.Blocks, nil, []}], &1))
      |> Ecto.Changeset.put_change(:publish_at, at(-1))
      |> Pages.update_page(c.user)

      assert Brando.Repo.get(Page, target.id).status == :published
      assert stored(target) =~ ~s(<div class="card" data-status="published">Launch</div>)
    end

    test "a publish_at set ahead on a published entry that passes while the form renders keeps the card", c do
      target = create_self_linking_page(c.user, c.module, %{status: :published})
      assert stored(target) =~ ~s(class="card")
      {:ok, entry} = Brando.Query.get_entry(Page, target.id)

      # Rendered as pending while the date is ahead, saved published once it has passed
      entry
      |> Page.changeset(%{publish_at: at(3600)}, c.user)
      |> then(&BrandoAdmin.Components.Form.render_blocks_for_save([{:blocks, Page.Blocks, nil, []}], &1))
      |> Ecto.Changeset.put_change(:publish_at, at(-1))
      |> Pages.update_page(c.user)

      assert Brando.Repo.get(Page, target.id).status == :published
      assert stored(target) =~ ~s(<div class="card" data-status="published">Launch</div>)
    end

    test "a save from a form opened before a publish elsewhere keeps the card", c do
      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module, %{
            code: @card <> "<h1>{{ entry.title }}</h1>",
            vars: [%{type: :link, key: "card", label: "Card", link_type: :identifier, creator_id: c.user.id}]
          }),
          :system
        )

      target = create_self_linking_page(c.user, module, %{status: :draft})
      {:ok, opened} = Brando.Query.get_entry(Page, target.id)

      {:ok, _} = Brando.Trait.Status.update_status(Page, target.id, :published, c.user)
      assert stored(target) =~ ~s(class="card")

      {:ok, _} = save_from_form_opened_as(opened, %{title: "Relaunch"}, c.user)
      assert Brando.Repo.get(Page, target.id).status == :published
      assert stored(target) =~ "<h1>Relaunch</h1>"
      assert stored(target) =~ ~s(<div class="card" data-status="published">)
    end

    test "a cascade queued and not started yet renders the entry for a status change it takes in", c do
      target = create_self_linking_page(c.user, c.module, %{status: :draft})

      rendered =
        rendered_by_cascade(fn ->
          {:ok, _} = update_target(target, %{title: "Renamed"}, c.user)
          {:ok, _} = Brando.Trait.Status.update_status(Page, target.id, :published, c.user)
          {:ok, _} = update_target(target, %{title: "Launch"}, c.user)
        end)

      assert rendered == [target.id]
    end

    test "a save from the form that renames the entry shows the new title and uri in its card", c do
      module =
        create_module(
          c.user,
          ~S({% assign e = card.identifier | get_entry %}<div class="card">{{ e.title }} {{ e.uri }}</div>)
        )

      target = create_self_linking_page(c.user, module, %{status: :published, uri: "launch"})
      assert stored(target) =~ ~s(<div class="card">Launch launch</div>)

      rendered =
        rendered_by_cascade(fn -> {:ok, _} = save_from_form(target, %{title: "Relaunch", uri: "relaunch"}, c.user) end)

      assert stored(target) =~ ~s(<div class="card">Relaunch relaunch</div>)
      refute target.id in rendered
    end

    test "a save from the form keeps the card's associations loaded, and loads one whose key it changes", c do
      module =
        create_module(
          c.user,
          ~S({% assign e = card.identifier | get_entry %}<div class="card">{{ e.title }} in {{ e.parent.title }}</div>)
        )

      work = create_target(c.user, %{title: "Work", status: :published})
      archive = create_target(c.user, %{title: "Archive", status: :published})
      target = create_self_linking_page(c.user, module, %{status: :published, parent_id: work.id})
      assert stored(target) =~ ~s(<div class="card">Launch in Work</div>)

      # A form whose entry has only its blocks loaded
      opened = Page |> Brando.Repo.get!(target.id) |> Brando.Repo.preload(Brando.Content.BlockPreloads.for_schema(Page))
      refute Ecto.assoc_loaded?(opened.parent)
      {:ok, _} = save_from_form_opened_as(opened, %{title: "Relaunch"}, c.user)
      assert stored(target) =~ ~s(<div class="card">Relaunch in Work</div>)

      # A form whose entry has the old parent loaded
      {:ok, _} = save_from_form(target, %{parent_id: archive.id}, c.user)
      assert stored(target) =~ ~s(<div class="card">Relaunch in Archive</div>)
    end

    test "a save from a form opened before a rename elsewhere shows the new title, where it does not change it", c do
      module =
        create_module(
          c.user,
          ~S({% assign e = card.identifier | get_entry %}<div class="card">{{ e.title }} {{ e.uri }}</div><h1>{{ entry.title }}</h1>)
        )

      target = create_self_linking_page(c.user, module, %{status: :published, uri: "launch"})
      {:ok, opened} = Brando.Query.get_entry(Page, target.id)

      {:ok, _} = update_target(target, %{title: "Renamed"}, c.user)

      {:ok, _} = save_from_form_opened_as(opened, %{uri: "relaunch"}, c.user)
      assert Brando.Repo.get(Page, target.id).title == "Renamed"
      assert stored(target) =~ ~s(<div class="card">Renamed relaunch</div><h1>Renamed</h1>)
    end

    test "a save from the form leaves a card of another entry as it is stored", c do
      module =
        create_module(c.user, ~S({% assign e = card.identifier | get_entry %}<div class="card">{{ e.title }}</div>))

      target = create_target(c.user, %{status: :published})
      page = create_linking_page(c.user, module, target)
      assert stored(page) =~ ~s(<div class="card">Launch</div>)

      {:ok, _} = save_from_form(page, %{title: "Relaunch"}, c.user)
      assert stored(page) =~ ~s(<div class="card">Launch</div>)
    end

    test "live preview shows the card with the entry as the form has it", c do
      module =
        create_module(
          c.user,
          ~S({% assign e = card.identifier | get_entry %}<div class="card">{{ e.title }} in {{ e.parent.title }}</div>)
        )

      work = create_target(c.user, %{title: "Work", status: :published})
      target = create_self_linking_page(c.user, module, %{status: :draft, parent_id: work.id})

      {:ok, entry} = Brando.Query.get_entry(Page, target.id)
      in_form = entry |> Page.changeset(%{title: "Relaunch"}, c.user) |> Ecto.Changeset.apply_changes()
      cache_key = "get-entry-#{System.unique_integer([:positive])}"
      on_exit(fn -> Brando.LivePreview.cleanup_cache(cache_key) end)

      assert Brando.LivePreview.render(Page, in_form, cache_key, target: :blocks) =~
               ~s(<div class="card">Relaunch in Work</div>)
    end

    test "a status change from the listing shows and hides the card", c do
      target = create_self_linking_page(c.user, c.module, %{status: :draft})

      {:ok, _} = Brando.Trait.Status.update_status(Page, target.id, :published, c.user)
      assert stored(target) =~ ~s(<div class="card" data-status="published">Launch</div>)

      {:ok, _} = Brando.Trait.Status.update_status(Page, target.id, :draft, c.user)
      assert stored(target) =~ ~s(class="no-card")
    end

    test "a status change from the listing with group authorization shows and hides the card", c do
      target = create_self_linking_page(c.user, c.module, %{status: :draft})

      Brando.Test.Support.put_test_env(:authorization_mode, :groups)
      Brando.Test.Support.put_test_env(:tenancy_mode, :none)
      Brando.Authorization.Boundary.put_scope(nil)
      {:ok, _} = Brando.Authorization.Migration.run()

      {:ok, _} = Brando.Trait.Status.update_status(Page, target.id, :published, c.user)
      assert stored(target) =~ ~s(class="card")

      {:ok, _} = Brando.Trait.Status.update_status(Page, target.id, :disabled, c.user)
      assert stored(target) =~ ~s(class="no-card")
    end

    test "the publish_at job shows the card and the unpublish_at job hides it", c do
      target = create_self_linking_page(c.user, c.module, %{status: :published, publish_at: at(3600)})
      assert Brando.Repo.get(Page, target.id).status == :pending
      assert stored(target) =~ ~s(class="no-card")

      BrandoIntegration.Repo.update_all(from(p in Page, where: p.id == ^target.id), set: [publish_at: at(-1)])

      assert :ok =
               perform_job(EntryPublisher, %{
                 "schema" => to_string(Page),
                 "id" => target.id,
                 "status" => "published",
                 "user_id" => c.user.id
               })

      assert stored(target) =~ ~s(<div class="card" data-status="published">Launch</div>)

      BrandoIntegration.Repo.update_all(from(p in Page, where: p.id == ^target.id), set: [unpublish_at: at(-1)])

      assert :ok =
               perform_job(EntryPublisher, %{
                 "schema" => to_string(Page),
                 "id" => target.id,
                 "status" => "disabled",
                 "user_id" => c.user.id
               })

      assert stored(target) =~ ~s(class="no-card")
    end

    test "a publish_at the sweep finds passed shows the card", c do
      target = create_self_linking_page(c.user, c.module, %{status: :published, publish_at: at(3600)})
      assert stored(target) =~ ~s(class="no-card")

      BrandoIntegration.Repo.update_all(from(p in Page, where: p.id == ^target.id), set: [publish_at: at(-600)])
      Brando.Publisher.sweep()

      assert stored(target) =~ ~s(class="card")
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
