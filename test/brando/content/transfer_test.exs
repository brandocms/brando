defmodule Brando.Content.TransferTest do
  use Brando.ConnCase, async: false
  alias Brando.Content.{Block, Transfer}
  alias Brando.Content.Transfer.{Catalog, Receipt}
  alias Brando.{Factory, Repo}
  alias Brando.Pages.Page
  alias Brando.Villain.Blocks.GalleryObjectOverride
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)
    source = Factory.insert(:page, creator: user, title: "Source", status: :draft)
    target = Factory.insert(:page, creator: user, title: "Destination", status: :draft)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Text"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.body %}",
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Default"}}}]
        ),
        user
      )

    params = %{
      "uid" => Brando.Utils.generate_uid(),
      "type" => "module",
      "module_id" => module.id,
      "creator_id" => user.id,
      "source" => to_string(Page.Blocks),
      "refs" => [
        %{
          "uid" => Brando.Utils.generate_uid(),
          "name" => "body",
          "data" => %{"type" => "text", "data" => %{"text" => "<p>Saved content</p>"}}
        }
      ]
    }

    block = %Block{} |> Block.recursive_block_changeset(params, user) |> Repo.insert!()
    struct(Page.Blocks, %{entry_id: source.id, block_id: block.id, sequence: 0}) |> Repo.insert!()
    %{user: user, source: source, target: target, module: module, block: block}
  end

  defp export(c, opts \\ []) do
    assert {:ok, exported} = Transfer.export([%{schema: Page, id: c.source.id, fields: ["blocks"]}], c.user, opts)
    assert {:ok, archive} = Transfer.read(exported.binary)
    archive
  end

  defp preview(c, archive, mode \\ "replace", dependencies \\ %{}) do
    [field] = archive.bundle["fields"]

    assert {:ok, plan} =
             Transfer.preview(
               archive,
               %{
                 field["key"] => %{"schema" => to_string(Page), "id" => c.target.id, "field" => "blocks", "mode" => mode}
               },
               c.user,
               dependencies: dependencies
             )

    plan
  end

  defp blocks(page, user), do: Catalog.load!(Page, page.id, user).entry_blocks |> Enum.map(& &1.block)

  defp entry_archive(c, selectors \\ nil) do
    assert {:ok, exported} = Transfer.export(selectors || [%{schema: Page, id: c.source.id}], c.user, media: false)
    assert {:ok, archive} = Transfer.read(exported.binary)
    archive
  end

  test "reusing an included parent preserves its content and excludes its unused media", c do
    c.source |> Changeset.change(parent_id: c.target.id) |> Repo.update!()
    image = Factory.insert(:image, title: "Parent only", path: "images/parent-only.jpg", creator_id: c.user.id)
    c.target |> Changeset.change(meta_image_id: image.id) |> Repo.update!()
    before = c.target |> then(&Transfer.EntryCodec.load!(Page, &1.id, c.user)) |> Transfer.EntryCodec.fingerprint()
    archive = entry_archive(c, [%{schema: Page, id: c.source.id}, %{schema: Page, id: c.target.id}])
    source_key = "#{Page}:#{c.source.id}"
    parent_key = "#{Page}:#{c.target.id}"

    targets = %{
      source_key => %{"attributes" => %{"uri" => "reused-parent-copy"}},
      parent_key => %{"mode" => "reuse", "id" => c.target.id}
    }

    assert {:ok, plan} = Transfer.preview(archive, targets, c.user)
    assert plan.problems == []
    refute Enum.any?(plan.dependencies, &(&1.dependency["source_id"] == image.id && &1.dependency["kind"] == "image"))
    assert {:ok, receipt} = Transfer.apply(plan, c.user)
    assert map_size(receipt.after) == 1
    refute Map.has_key?(receipt.before, parent_key)
    created = Repo.get!(Page, receipt.after[source_key]["id"])
    assert created.parent_id == c.target.id
    assert before == Transfer.EntryCodec.fingerprint(Transfer.EntryCodec.load!(Page, c.target.id, c.user))
    assert {:ok, _} = Transfer.restore(receipt.id, c.user)
    assert before == Transfer.EntryCodec.fingerprint(Transfer.EntryCodec.load!(Page, c.target.id, c.user))
  end

  test "catalog type filters are combined before limiting results", c do
    Brando.Content.create_identifier(Page, c.source)
    results = Catalog.search(c.user, "", entries: true, schemas: [to_string(Page)])
    assert [_ | _] = results
    source = Enum.find(results, &(&1.id == c.source.id))
    assert source.creator_name == c.user.name
    assert source.updated_at == c.source.updated_at

    assert Enum.all?(
             Catalog.search(c.user, "", entries: true, schemas: [to_string(Page)]),
             &(&1.schema == to_string(Page))
           )

    assert [] == Catalog.search(c.user, "", entries: true, schemas: ["Unregistered.Type"])
  end

  test "media mapping options include untitled assets and search their filenames", c do
    image = Factory.insert(:image, title: nil, path: "images/untitled-courtyard.jpg", creator_id: c.user.id)
    options = Transfer.Dependencies.options("image", c.user)
    assert Enum.any?(options, &(&1.id == image.id && &1.label == image.path))
    assert [%{id: id}] = Transfer.Dependencies.options("image", c.user, "untitled-courtyard")
    assert id == image.id
  end

  test "whole entries carry authored metadata and owned variables, create as drafts, and recover", c do
    c.source
    |> Changeset.change(
      status: :published,
      meta_title: "Campaign SEO",
      css_classes: "campaign",
      publish_at: DateTime.add(DateTime.utc_now(), 86400) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    Brando.Content.Var.changeset(
      %Brando.Content.Var{},
      %{type: :string, key: "strapline", label: "Strapline", value: "Made here", page_id: c.source.id},
      c.user
    )
    |> Repo.insert!()

    archive = entry_archive(c)
    assert archive.bundle["version"] == 2
    [entry] = archive.bundle["entries"]
    assert entry["data"]["attributes"]["meta_title"] == "Campaign SEO"
    assert [var] = entry["data"]["owned"]["vars"]
    assert var["attributes"]["value"] == "Made here"
    refute Map.has_key?(var["attributes"], "id")
    targets = %{entry["key"] => %{"attributes" => %{"uri" => "new-campaign"}}}
    assert {:ok, plan} = Transfer.preview(archive, targets, c.user)
    assert plan.problems == []
    assert {:ok, receipt} = Transfer.apply(plan, c.user)
    saved = Repo.get!(Page, receipt.after[entry["key"]]["id"]) |> Brando.Content.Transfer.EntryCodec.preload()
    assert saved.id != c.source.id
    assert saved.status == :draft
    assert is_nil(saved.publish_at)
    assert Repo.get_by(Brando.Content.Identifier, schema: Page, entry_id: saved.id)
    assert saved.meta_title == "Campaign SEO"
    assert saved.css_classes == "campaign"
    assert saved.uri == "new-campaign"
    assert [saved_var] = saved.vars
    assert saved_var.value == "Made here"
    assert saved_var.page_id == saved.id
    assert hd(saved.entry_blocks).block.uid != c.block.uid
    assert {:ok, retried} = Transfer.apply(plan, c.user)
    assert retried.id == receipt.id
    assert {:ok, _} = Transfer.restore(receipt.id, c.user)
    assert is_nil(Repo.get(Page, saved.id))
    refute Repo.get!(Page, c.source.id).deleted_at
  end

  test "whole entry updates preserve publication, review conflicts and recover metadata", c do
    archive = entry_archive(c)
    [entry] = archive.bundle["entries"]
    assert {:ok, conflict} = Transfer.preview(archive, %{}, c.user)
    assert Enum.any?(conflict.problems, &String.contains?(&1, "already in use"))
    c.target |> Changeset.change(status: :published, meta_title: "Original SEO") |> Repo.update!()
    targets = %{entry["key"] => %{"mode" => "update", "id" => c.target.id, "attributes" => %{"uri" => c.target.uri}}}
    assert {:ok, plan} = Transfer.preview(archive, targets, c.user)
    assert plan.problems == []

    assert Enum.any?(
             hd(plan.entries).changes,
             &(&1.field == "title" && &1.before == "Destination" && &1.after == "Source")
           )

    assert {:ok, receipt} = Transfer.apply(plan, c.user)
    updated = Repo.get!(Page, c.target.id)
    assert updated.title == "Source"
    assert updated.status == :published
    assert {:ok, _} = Transfer.restore(receipt.id, c.user)
    restored = Repo.get!(Page, c.target.id)
    assert restored.title == "Destination"
    assert restored.meta_title == "Original SEO"
    assert restored.status == :published
    assert blocks(c.target, c.user) == []
  end

  test "included parent entries remap their identities and a changed entry blocks recovery", c do
    c.source |> Changeset.change(parent_id: c.target.id) |> Repo.update!()
    archive = entry_archive(c, [%{schema: Page, id: c.source.id}, %{schema: Page, id: c.target.id}])

    targets =
      Map.new(archive.bundle["entries"], fn entry ->
        {entry["key"], %{"attributes" => %{"uri" => "copied-" <> entry["hints"]["uri"]}}}
      end)

    assert {:ok, plan} = Transfer.preview(archive, targets, c.user)
    assert plan.problems == []
    assert Enum.any?(plan.dependencies, &(&1.action == :bundle))
    assert {:ok, receipt} = Transfer.apply(plan, c.user)
    source_id = receipt.after["#{Page}:#{c.source.id}"]["id"]
    parent_id = receipt.after["#{Page}:#{c.target.id}"]["id"]
    copied = Repo.get!(Page, source_id)
    assert copied.parent_id == parent_id
    copied |> Changeset.change(meta_description: "Newer edit") |> Repo.update!()
    assert {:error, message} = Transfer.restore(receipt.id, c.user)
    assert message =~ "newer edits"
    refute Repo.get!(Page, parent_id).deleted_at
  end

  test "whole entry metadata JSON is ordinary authored data and references require mapping", c do
    crumbs = [%{"image_id" => 723, "source_id" => 918, "title" => "A custom breadcrumb"}]
    c.source |> Changeset.change(breadcrumbs: crumbs, parent_id: c.target.id) |> Repo.update!()
    archive = entry_archive(c)
    [entry] = archive.bundle["entries"]
    assert entry["data"]["attributes"]["breadcrumbs"] == crumbs
    targets = %{entry["key"] => %{"attributes" => %{"uri" => "json-content"}}}
    assert {:ok, unresolved} = Transfer.preview(archive, targets, c.user)
    assert Enum.any?(unresolved.dependencies, &(&1.action == :unresolved && &1.dependency["kind"] == "entry"))
    token = entry["data"]["references"]["parent"]
    assert {:ok, plan} = Transfer.preview(archive, targets, c.user, dependencies: %{token => c.target.id})
    assert plan.problems == []
    assert {:ok, receipt} = Transfer.apply(plan, c.user)
    saved = Repo.get!(Page, receipt.after[entry["key"]]["id"])
    assert saved.breadcrumbs == crumbs
    assert saved.parent_id == c.target.id
  end

  test "entry recovery refuses to remove newly referenced content", c do
    archive = entry_archive(c)
    [entry] = archive.bundle["entries"]

    assert {:ok, plan} =
             Transfer.preview(archive, %{entry["key"] => %{"attributes" => %{"uri" => "new-referenced-entry"}}}, c.user)

    assert {:ok, receipt} = Transfer.apply(plan, c.user)
    copied_id = receipt.after[entry["key"]]["id"]
    child = Factory.insert(:page, creator: c.user, parent_id: copied_id)
    assert {:error, message} = Transfer.restore(receipt.id, c.user)
    assert message =~ "now references"
    assert Repo.get(Page, copied_id)
    assert Repo.get(Page, child.id)
    Repo.delete!(child)
    identifier = Repo.get_by!(Brando.Content.Identifier, schema: Page, entry_id: copied_id)

    c.source
    |> Changeset.change(
      meta_description: "<a data-identifier-id='#{identifier.id}' href='/new-referenced-entry'>Read more</a>"
    )
    |> Repo.update!()

    assert {:error, message} = Transfer.restore(receipt.id, c.user)
    assert message =~ "now references"
    assert Repo.get(Page, copied_id)
  end

  test "owned gallery variables keep separate placements and recover their values", c do
    image = Factory.insert(:image)

    gallery =
      Brando.Galleries.Gallery.changeset(
        %Brando.Galleries.Gallery{},
        %{"config_target" => "default", "gallery_objects" => [%{"image_id" => image.id}]},
        c.user
      )
      |> Repo.insert!()

    for key <- ["gallery_one", "gallery_two"] do
      Brando.Content.Var.changeset(
        %Brando.Content.Var{},
        %{type: :gallery, key: key, label: key, gallery_id: gallery.id, page_id: c.source.id},
        c.user
      )
      |> Repo.insert!()
    end

    archive = entry_archive(c)
    [entry] = archive.bundle["entries"]
    targets = %{entry["key"] => %{"mode" => "update", "id" => c.target.id, "attributes" => %{"uri" => c.target.uri}}}
    assert {:ok, plan} = Transfer.preview(archive, targets, c.user, dependencies: %{"image:#{image.id}" => image.id})
    assert plan.problems == []
    assert {:ok, receipt} = Transfer.apply(plan, c.user)
    target = Brando.Content.Transfer.EntryCodec.load!(Page, c.target.id, c.user)
    assert [first, second] = target.vars
    assert first.gallery_id != second.gallery_id
    assert first.gallery_id != gallery.id
    assert second.gallery_id != gallery.id
    assert {:ok, _} = Transfer.restore(receipt.id, c.user)
    assert Brando.Content.Transfer.EntryCodec.load!(Page, c.target.id, c.user).vars == []
  end

  test "source publication schedules are applied, cleared for drafts and recovered", c do
    Oban.Testing.with_testing_mode(:manual, fn ->
      future = DateTime.utc_now() |> DateTime.add(86_400) |> DateTime.truncate(:second)
      c.source |> Changeset.change(status: :pending, publish_at: future) |> Repo.update!()
      archive = entry_archive(c)
      [entry] = archive.bundle["entries"]
      target = %{"attributes" => %{"uri" => "scheduled-entry-copy"}, "publication" => "source"}
      assert {:ok, plan} = Transfer.preview(archive, %{entry["key"] => target}, c.user)
      assert plan.problems == []
      assert hd(plan.entries).status == :pending
      assert {:ok, receipt} = Transfer.apply(plan, c.user)
      id = receipt.after[entry["key"]]["id"]

      jobs = fn ->
        Repo.all(Oban.Job) |> Enum.filter(&(&1.worker == "Brando.Worker.EntryPublisher" && &1.args["id"] == id))
      end

      assert [job] = jobs.()
      assert DateTime.compare(job.scheduled_at, future) == :eq
      target = Map.merge(target, %{"mode" => "update", "id" => id, "publication" => "draft"})
      assert {:ok, draft} = Transfer.preview(archive, %{entry["key"] => target}, c.user)
      assert draft.problems == []
      assert {:ok, update} = Transfer.apply(draft, c.user)
      assert Repo.get!(Page, id).status == :draft
      assert is_nil(Repo.get!(Page, id).publish_at)
      assert jobs.() == []
      assert {:ok, _} = Transfer.restore(update.id, c.user)
      assert Repo.get!(Page, id).status == :pending
      assert Repo.get!(Page, id).publish_at == future
      assert [_] = jobs.()
    end)
  end

  test "unique keys are checked across incoming entries before apply", c do
    archive = entry_archive(c, [%{schema: Page, id: c.source.id}, %{schema: Page, id: c.target.id}])
    targets = Map.new(archive.bundle["entries"], &{&1["key"], %{"attributes" => %{"uri" => "same-new-key"}}})
    assert {:ok, plan} = Transfer.preview(archive, targets, c.user)
    assert Enum.any?(plan.problems, &String.contains?(&1, "same unique key"))
    assert {:error, _} = Transfer.apply(plan, c.user)
    refute Repo.get_by(Page, uri: "same-new-key")
  end

  test "new entries keep self-links and mutual identifier references", c do
    {:ok, source_link} = Brando.Content.create_identifier(Page, c.source)
    {:ok, target_link} = Brando.Content.create_identifier(Page, c.target)

    for {page, link} <- [{c.source, source_link}, {c.source, target_link}, {c.target, source_link}] do
      Brando.Content.Var.changeset(
        %Brando.Content.Var{},
        %{
          type: :link,
          key: "link_#{link.id}",
          label: "Entry link",
          link_type: :identifier,
          identifier_id: link.id,
          page_id: page.id
        },
        c.user
      )
      |> Repo.insert!()
    end

    archive = entry_archive(c, [%{schema: Page, id: c.source.id}, %{schema: Page, id: c.target.id}])

    targets =
      Map.new(
        archive.bundle["entries"],
        &{&1["key"], %{"attributes" => %{"uri" => "linked-copy-" <> &1["hints"]["uri"]}}}
      )

    assert {:ok, plan} = Transfer.preview(archive, targets, c.user)
    assert plan.problems == []
    assert {:ok, receipt} = Transfer.apply(plan, c.user)
    copied_source = receipt.after["#{Page}:#{c.source.id}"]["id"]
    copied_target = receipt.after["#{Page}:#{c.target.id}"]["id"]
    source = Brando.Content.Transfer.EntryCodec.load!(Page, copied_source, c.user)
    target = Brando.Content.Transfer.EntryCodec.load!(Page, copied_target, c.user)

    linked_ids = fn vars ->
      Enum.map(vars, &Repo.get!(Brando.Content.Identifier, &1.identifier_id).entry_id) |> Enum.sort()
    end

    assert linked_ids.(source.vars) == Enum.sort([copied_source, copied_target])
    assert linked_ids.(target.vars) == [copied_source]
    assert {:ok, _} = Transfer.restore(receipt.id, c.user)
    assert is_nil(Repo.get(Page, copied_source))
    assert is_nil(Repo.get(Page, copied_target))
  end

  test "portable archive, read-only preview, fresh identities and recoverable replace", c do
    archive = export(c)
    assert archive.bundle["definitions"]
    assert hd(archive.bundle["fields"])["blocks"] |> hd() |> Map.get("module_id") == "module:#{c.module.id}"
    plan = preview(c, archive)
    assert plan.problems == []
    assert blocks(c.target, c.user) == []
    assert Repo.aggregate(Receipt, :count) == 0
    assert {:ok, receipt} = Transfer.apply(plan, c.user)
    [copied] = blocks(c.target, c.user)
    assert copied.id != c.block.id
    assert copied.uid != c.block.uid
    assert copied.module_id == c.module.id
    assert copied.module_version == c.module.version
    assert copied.creator_id == c.user.id
    assert copied.source == Page.Blocks
    assert hd(copied.refs).data.data.text == "<p>Saved content</p>"
    assert {:ok, _} = Transfer.restore(receipt.id, c.user)
    assert blocks(c.target, c.user) == []
  end

  test "retry is idempotent; separately reviewed append is intentional", c do
    archive = export(c)
    plan = preview(c, archive, "append")
    assert {:ok, first} = Transfer.apply(plan, c.user)
    assert {:ok, %{id: id}} = Transfer.apply(plan, c.user)
    assert id == first.id
    assert length(blocks(c.target, c.user)) == 1
    assert {:ok, _} = Transfer.apply(preview(c, archive, "append"), c.user)
    assert length(blocks(c.target, c.user)) == 2
  end

  test "changed destination invalidates apply and recovery", c do
    archive = export(c)
    plan = preview(c, archive)
    c.target |> Changeset.change(title: "Changed concurrently") |> Repo.update!()
    assert {:error, message} = Transfer.apply(plan, c.user)
    assert message =~ "changed"
    assert blocks(c.target, c.user) == []
    assert {:ok, receipt} = Transfer.apply(preview(c, archive), c.user)
    [block] = blocks(c.target, c.user)
    block |> Changeset.change(description: "Another editor") |> Repo.update!()
    assert {:error, message} = Transfer.restore(receipt.id, c.user)
    assert message =~ "newer edits"
  end

  test "lineage mapping never guesses from coincident numeric IDs", c do
    archive = export(c)
    original_uid = c.module.uid
    c.module |> Changeset.change(uid: "unrelated-uid") |> Repo.update!()

    {:ok, destination_module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          uid: original_uid,
          name: %{"en" => "Destination text"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.body %}",
          refs: [%{name: "body", data: %{type: "text", data: %{text: "Different default"}}}]
        ),
        c.user
      )

    assert destination_module.id != c.module.id
    plan = preview(c, archive)
    assert plan.problems == []
    assert hd(plan.dependencies).differences == ["refs"]
    assert {:ok, _} = Transfer.apply(plan, c.user)
    assert hd(blocks(c.target, c.user)).module_id == destination_module.id
  end

  test "historical copies need explicit mapping; incompatible contracts block", c do
    archive = export(c)
    c.module |> Changeset.change(uid: "historical-copy") |> Repo.update!()
    plan = preview(c, archive)
    assert plan.problems != []
    assert Enum.any?(hd(plan.dependencies).suggestions, &(&1.match == :suggestion))
    assert {:ok, _} = Transfer.apply(preview(c, archive, "replace", %{"module:#{c.module.id}" => c.module.id}), c.user)
    ref = Repo.preload(c.module, :refs).refs |> hd()
    ref |> Brando.Content.Ref.changeset(%{data: %{type: "header", data: %{text: "Retyped"}}}, c.user) |> Repo.update!()
    assert preview(c, archive, "replace", %{"module:#{c.module.id}" => c.module.id}).problems != []
  end

  test "archive rejects source IDs used as references and cross-actor plans", c do
    archive = export(c)
    [field] = archive.bundle["fields"]
    tampered = put_in(archive, [:bundle, "fields"], [put_in(field, ["blocks", Access.at(0), "module_id"], c.module.id)])
    assert {:error, _} = Transfer.preview(tampered, %{}, c.user)
    plan = preview(c, archive)
    assert {:error, message} = Transfer.apply(plan, Factory.insert(:random_user))
    assert message =~ "another actor"
    assert blocks(c.target, c.user) == []
  end

  test "rich-text links, selection order and metadata bind to reviewed destination identifiers", c do
    {:ok, source_identifier} = Brando.Content.create_identifier(Page, c.source)
    {:ok, target_identifier} = Brando.Content.create_identifier(Page, c.target)
    ref = Repo.preload(c.block, :refs).refs |> hd()

    data =
      put_in(
        ref.data,
        [Access.key(:data), Access.key(:text)],
        ~s(<p><a href="/source" data-identifier-id="#{source_identifier.id}">Read more</a></p>)
      )

    ref |> Changeset.change(data: data) |> Repo.update!()

    c.block
    |> Changeset.change(identifier_metas: %{"#{inspect(Page)}_#{c.source.id}" => %{"caption" => "Selected caption"}})
    |> Repo.update!()

    Repo.insert!(%Brando.Content.BlockIdentifier{block_id: c.block.id, identifier_id: source_identifier.id, sequence: 0})
    archive = export(c)
    unresolved = preview(c, archive)
    assert unresolved.problems != []
    plan = preview(c, archive, "replace", %{"identifier:#{source_identifier.id}" => target_identifier.id})
    assert plan.problems == []
    assert {:ok, _} = Transfer.apply(plan, c.user)
    [block] = blocks(c.target, c.user)
    assert hd(block.block_identifiers).identifier_id == target_identifier.id
    assert block.identifier_metas["#{inspect(Page)}_#{c.target.id}"] == %{"caption" => "Selected caption"}
    html = hd(block.refs).data.data.text
    assert html =~ ~s(data-identifier-id="#{target_identifier.id}")
    assert html =~ ~s(href="#{target_identifier.url}")
  end

  test "media originals and gallery objects receive new ownership and override identities", c do
    image = c.user.avatar

    gallery =
      %Brando.Galleries.Gallery{}
      |> Brando.Galleries.Gallery.changeset(
        %{
          "config_target" => "default",
          "gallery_objects" => [%{"image_id" => image.id, "config" => %{"caption" => "Gallery placement"}}]
        },
        c.user
      )
      |> Repo.insert!()

    gallery_ref = %{
      name: "gallery",
      gallery_id: gallery.id,
      uid: Brando.Utils.generate_uid(),
      data: %{
        type: "gallery",
        data: %{
          gallery_object_overrides: [%{object_id: to_string(image.id), object_type: "image", title: "Default title"}]
        }
      }
    }

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Gallery"},
          namespace: %{},
          help_text: %{},
          code: "Gallery",
          refs: [gallery_ref]
        ),
        c.user
      )

    params = %{
      "uid" => Brando.Utils.generate_uid(),
      "type" => "module",
      "module_id" => module.id,
      "source" => to_string(Page.Blocks),
      "creator_id" => c.user.id,
      "refs" => [
        %{
          "uid" => Brando.Utils.generate_uid(),
          "name" => "gallery",
          "gallery_id" => gallery.id,
          "data" => %{
            "type" => "gallery",
            "data" => %{
              "gallery_object_overrides" => [
                %{
                  "object_id" => to_string(image.id),
                  "object_type" => "image",
                  "title" => "My crop",
                  "use_default_title" => false
                }
              ]
            }
          }
        }
      ]
    }

    block = %Block{} |> Block.recursive_block_changeset(params, c.user) |> Repo.insert!()
    Repo.insert!(struct(Page.Blocks, %{entry_id: c.source.id, block_id: block.id, sequence: 1}))
    archive = export(c)
    assert map_size(archive.files) == 1
    plan = preview(c, archive)
    assert plan.problems == []
    assert {:ok, _} = Transfer.apply(plan, c.user)
    [_text, imported] = blocks(c.target, c.user)
    [ref] = imported.refs
    assert ref.gallery_id != gallery.id
    [copied_object] = ref.gallery.gallery_objects
    assert copied_object.image_id != image.id
    assert copied_object.config["caption"] == "Gallery placement"
    [override] = ref.data.data.gallery_object_overrides
    assert override.object_id == to_string(copied_object.image_id)
    assert override.title == "My crop"
    original = Brando.Content.Transfer.Media.read_original!("image", image)
    assert original == Brando.Content.Transfer.Media.read_original!("image", copied_object.image)
    repeat = preview(c, archive)
    media = Enum.find(repeat.dependencies, &(&1.dependency["kind"] == "image"))
    assert media.action == :reuse
    assert Enum.any?(media.suggestions, &(&1.match == :checksum))
    separate = preview(c, archive, "replace", %{media.token => "create"})
    assert Enum.find(separate.dependencies, &(&1.token == media.token)).action == :create
    [incoming_field] = archive.bundle["fields"]
    failing_field = put_in(incoming_field, ["blocks", Access.at(0), "description"], "reject-transfer-media")
    failing_archive = put_in(archive, [:bundle, "fields"], [failing_field])
    failing = preview(c, failing_archive, "replace", %{media.token => "create"})

    Ecto.Adapters.SQL.query!(
      Repo.repo(),
      "ALTER TABLE content_blocks ADD CONSTRAINT reject_transfer_media CHECK (description IS DISTINCT FROM 'reject-transfer-media') NOT VALID"
    )

    image_count = Repo.aggregate(Brando.Images.Image, :count)
    gallery_count = Repo.aggregate(Brando.Galleries.Gallery, :count)
    assert {:error, _} = Transfer.apply(failing, c.user)
    assert Repo.aggregate(Brando.Images.Image, :count) == image_count
    assert Repo.aggregate(Brando.Galleries.Gallery, :count) == gallery_count
    config = Brando.Content.Transfer.Media.config!("image", media.dependency["data"], c.user)

    failed_path =
      Path.join([
        Brando.Tenant.Storage.current_media_root(),
        config.upload_path,
        failing.id <> "-" <> String.replace(media.token, ":", "-") <> Path.extname(image.path)
      ])

    refute File.exists?(failed_path)
    assert Path.wildcard(Path.join(System.tmp_dir!(), "brando-content-#{failing.id}-*")) == []

    # One dependency can occur in multiple source fields. Every destination
    # placement owns a distinct gallery, including after recovery.
    other = Factory.insert(:page, creator: c.user, title: "Other destination", status: :draft)
    [field] = archive.bundle["fields"]
    other_field = %{field | "key" => field["key"] <> ":other"}
    multi = put_in(archive, [:bundle, "fields"], [field, other_field])

    targets = %{
      field["key"] => %{"schema" => to_string(Page), "id" => c.target.id, "field" => "blocks"},
      other_field["key"] => %{"schema" => to_string(Page), "id" => other.id, "field" => "blocks"}
    }

    assert {:ok, plan} = Transfer.preview(multi, targets, c.user)
    assert plan.problems == []
    assert {:ok, receipt} = Transfer.apply(plan, c.user)
    [_text, first] = blocks(c.target, c.user)
    [_text, second] = blocks(other, c.user)
    assert hd(first.refs).gallery_id != hd(second.refs).gallery_id
    assert {:ok, _} = Transfer.restore(receipt.id, c.user)
    assert blocks(other, c.user) == []
    [_text, recovered] = blocks(c.target, c.user)
    assert recovered.uid != imported.uid
    assert recovered.module_version == module.version
    [recovered_ref] = recovered.refs
    assert recovered_ref.gallery_id != ref.gallery_id
    [recovered_object] = recovered_ref.gallery.gallery_objects
    assert recovered_object.image_id == copied_object.image_id
    assert hd(recovered_ref.data.data.gallery_object_overrides).object_id == to_string(recovered_object.image_id)
    assert hd(recovered_ref.data.data.gallery_object_overrides).title == "My crop"
  end

  # Image and video ids come from separate sequences; give both the same id so
  # an override only lands on the right item if it is matched by type as well.
  defp colliding_gallery_block(c) do
    image = c.user.avatar
    video = Factory.insert(:video, id: image.id, title: "Clip", creator_id: c.user.id)
    Ecto.Adapters.SQL.query!(Repo.repo(), "SELECT setval('videos_id_seq', (SELECT max(id) FROM videos))")

    gallery =
      %Brando.Galleries.Gallery{}
      |> Brando.Galleries.Gallery.changeset(
        %{
          "config_target" => "default",
          "gallery_objects" => [
            %{"image_id" => image.id, "sequence" => 0},
            %{"video_id" => video.id, "sequence" => 1}
          ]
        },
        c.user
      )
      |> Repo.insert!()

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Gallery"},
          namespace: %{},
          help_text: %{},
          code: "Gallery",
          refs: [%{name: "gallery", uid: Brando.Utils.generate_uid(), data: %{type: "gallery", data: %{}}}]
        ),
        c.user
      )

    overrides = [
      %{"object_id" => to_string(image.id), "object_type" => "image", "title" => "Image caption"},
      %{"object_id" => to_string(video.id), "object_type" => "video", "title" => "Video caption"},
      # No longer in the gallery, so it has nothing to travel with.
      %{"object_id" => "999999", "object_type" => "image", "title" => "Removed image"}
    ]

    params = %{
      "uid" => Brando.Utils.generate_uid(),
      "type" => "module",
      "module_id" => module.id,
      "source" => to_string(Page.Blocks),
      "creator_id" => c.user.id,
      "refs" => [
        %{
          "uid" => Brando.Utils.generate_uid(),
          "name" => "gallery",
          "gallery_id" => gallery.id,
          "data" => %{
            "type" => "gallery",
            "data" => %{
              "gallery_object_overrides" => Enum.map(overrides, &Map.put(&1, "use_default_title", false))
            }
          }
        }
      ]
    }

    block = %Block{} |> Block.recursive_block_changeset(params, c.user) |> Repo.insert!()
    Repo.insert!(struct(Page.Blocks, %{entry_id: c.source.id, block_id: block.id, sequence: 1}))
    %{image: image, video: video}
  end

  defp archive_overrides(archive) do
    [field] = archive.bundle["fields"]
    [_text, gallery_block] = field["blocks"]
    [ref] = gallery_block["refs"]
    ref["data"]["data"]["gallery_object_overrides"]
  end

  defp assert_overrides_follow_media(c) do
    [_text, imported] = blocks(c.target, c.user)
    [ref] = imported.refs
    objects = ref.gallery.gallery_objects
    image_object = Enum.find(objects, & &1.image_id)
    video_object = Enum.find(objects, & &1.video_id)
    overrides = ref.data.data.gallery_object_overrides
    index = GalleryObjectOverride.index(overrides)

    assert length(overrides) == 2
    assert GalleryObjectOverride.lookup(index, :image, image_object.image_id).title == "Image caption"
    assert GalleryObjectOverride.lookup(index, :video, video_object.video_id).title == "Video caption"
    ref
  end

  test "gallery overrides follow their image or video to the destination", c do
    %{image: image, video: video} = colliding_gallery_block(c)
    archive = export(c)

    assert Enum.map(archive_overrides(archive), &{&1["object_type"], &1["object_id"], &1["title"]}) == [
             {"image", "image:#{image.id}", "Image caption"},
             {"video", "video:#{video.id}", "Video caption"}
           ]

    plan = preview(c, archive)
    assert plan.problems == []
    assert {:ok, _} = Transfer.apply(plan, c.user)
    ref = assert_overrides_follow_media(c)
    assert Enum.all?(ref.gallery.gallery_objects, &(&1.image_id != image.id && &1.video_id != video.id))
  end

  test "archives exported before overrides were tokenized by media still import", c do
    %{image: image, video: video} = colliding_gallery_block(c)
    archive = export(c)

    # The previous exporter prefixed the stored media id with `gallery_object:`.
    legacy =
      update_in(archive, [:bundle, "fields", Access.at(0), "blocks", Access.at(1), "refs", Access.at(0)], fn ref ->
        update_in(ref, ["data", "data", "gallery_object_overrides"], fn overrides ->
          id = %{"image" => image.id, "video" => video.id}
          Enum.map(overrides, &Map.put(&1, "object_id", "gallery_object:#{id[&1["object_type"]]}"))
        end)
      end)

    assert {:ok, binary} = Brando.Content.Transfer.Archive.export(legacy.bundle, legacy.files)
    assert {:ok, read} = Transfer.read(binary)

    assert Enum.map(archive_overrides(read), &{&1["object_type"], &1["object_id"]}) == [
             {"image", "image:#{image.id}"},
             {"video", "video:#{video.id}"}
           ]

    plan = preview(c, read)
    assert plan.problems == []
    assert {:ok, _} = Transfer.apply(plan, c.user)
    assert_overrides_follow_media(c)
  end

  test "all destination mappings must be distinct and valid before any content is written", c do
    archive = export(c)
    [field] = archive.bundle["fields"]
    second = %{field | "key" => field["key"] <> ":other"}
    archive = put_in(archive, [:bundle, "fields"], [field, second])
    target = %{"schema" => to_string(Page), "id" => c.target.id, "field" => "blocks"}
    assert {:ok, duplicate} = Transfer.preview(archive, %{field["key"] => target, second["key"] => target}, c.user)
    assert Enum.any?(duplicate.problems, &String.contains?(&1, "distinct"))
    assert {:error, _} = Transfer.apply(duplicate, c.user)

    assert {:ok, invalid} =
             Transfer.preview(
               archive,
               %{field["key"] => target, second["key"] => %{target | "id" => 2_000_000_000}},
               c.user
             )

    assert {:error, _} = Transfer.apply(invalid, c.user)
    assert blocks(c.target, c.user) == []
    assert Repo.aggregate(Receipt, :count) == 0
  end

  test "a late database rejection rolls back every imported row", c do
    archive = export(c)

    Ecto.Adapters.SQL.query!(
      Repo.repo(),
      "ALTER TABLE content_blocks ADD CONSTRAINT reject_transfer_insert CHECK (description IS DISTINCT FROM 'reject-transfer') NOT VALID"
    )

    [field] = archive.bundle["fields"]

    archive =
      put_in(archive, [:bundle, "fields"], [put_in(field, ["blocks", Access.at(0), "description"], "reject-transfer")])

    plan = preview(c, archive)
    assert plan.problems == []
    count = Repo.aggregate(Block, :count)
    assert {:error, message} = Transfer.apply(plan, c.user)
    assert message =~ "constraint"
    assert Repo.aggregate(Block, :count) == count
    assert Repo.aggregate(Receipt, :count) == 0
    assert blocks(c.target, c.user) == []
  end

  test "table rows retain order and cell values with fresh IDs", c do
    {:ok, template} =
      Brando.Content.create_table_template(
        %{name: "Transfer table", vars: [%{key: "cell", label: "Cell", type: :string, creator_id: c.user.id}]},
        c.user
      )

    c.module |> Changeset.change(table_template_id: template.id) |> Repo.update!()

    rows =
      Enum.with_index(["First", "Second", "Third"], fn value, n ->
        %{sequence: n, vars: [%{key: "cell", label: "Cell", type: :string, value: value, creator_id: c.user.id}]}
      end)

    original =
      c.block
      |> Repo.preload(:table_rows)
      |> Changeset.change()
      |> Changeset.put_assoc(:table_rows, rows)
      |> Repo.update!()

    plan = preview(c, export(c))
    assert plan.problems == []
    assert {:ok, _} = Transfer.apply(plan, c.user)
    [copied] = blocks(c.target, c.user)
    assert Enum.map(copied.table_rows, & &1.sequence) == [0, 1, 2]
    assert Enum.map(copied.table_rows, &hd(&1.vars).value) == ["First", "Second", "Third"]
    refute Enum.any?(copied.table_rows, fn row -> Enum.any?(original.table_rows, &(&1.id == row.id)) end)
  end

  test "definition-only assets do not create unused content dependencies", c do
    module = Repo.preload(c.module, :refs)
    ref = %{name: "optional_picture", image_id: c.user.avatar.id, data: %{type: "picture", data: %{}}}
    ref = Brando.Content.Ref.changeset(%Brando.Content.Ref{}, ref, c.user)
    module |> Changeset.change() |> Changeset.put_assoc(:refs, module.refs ++ [ref]) |> Repo.update!()
    archive = export(c)
    assert archive.bundle["dependencies"]["image:#{c.user.avatar.id}"]
    plan = preview(c, archive)
    assert plan.problems == []
    assert Enum.map(plan.dependencies, & &1.dependency["kind"]) == ["module"]
    images = Repo.aggregate(Brando.Images.Image, :count)
    assert {:ok, _} = Transfer.apply(plan, c.user)
    assert Repo.aggregate(Brando.Images.Image, :count) == images
    [block] = blocks(c.target, c.user)
    assert Enum.find(block.refs, &(&1.name == "optional_picture")).image_id == c.user.avatar.id
  end

  test "unquoted rich-text identifiers cannot bypass portable reference validation", c do
    archive = export(c)
    [field] = archive.bundle["fields"]

    field =
      put_in(
        field,
        ["blocks", Access.at(0), "refs", Access.at(0), "data", "data", "text"],
        "<a data-identifier-id=123 href='/source'>Link</a>"
      )

    assert {:error, message} = Transfer.preview(put_in(archive, [:bundle, "fields"], [field]), %{}, c.user)
    assert message =~ "Database IDs"
  end

  test "revoked grants, inactive accounts and a different environment cannot reuse a preview", c do
    tenancy_mode = Brando.config(:tenancy_mode)
    archive = export(c)
    plan = preview(c, archive)
    put_test_env(:tenancy_mode, :multi)

    Brando.Tenant.with_prefix("tenant_transfer_staging", fn ->
      assert {:error, _} = Transfer.apply(plan, c.user)
    end)

    put_test_env(:tenancy_mode, tenancy_mode)
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Brando.Authorization.Migration.run()
    editor = Factory.insert(:random_user, role: :user)
    alias Brando.Authorization.{Catalog, Groups, Scope}
    scope = Scope.standalone(c.user)

    grants = [
      Catalog.get(:read, Page).key,
      Catalog.get(:update, Page).key,
      Catalog.get(:read, Brando.Content.Module).key,
      "brando.admin.access"
    ]

    {:ok, group} = Groups.create(scope, %{name: "Transfer editors"}, grants)
    {:ok, :ok} = Groups.add_member(scope, group.id, editor.id)
    plan = preview(%{c | user: editor}, archive)
    assert plan.problems == []
    c.target |> Changeset.change(status: :published) |> Repo.update!()
    refute Transfer.applicable?(preview(%{c | user: editor}, archive))
    Repo.get!(Page, c.target.id) |> Changeset.change(status: :draft) |> Repo.update!()
    assert {:ok, _} = Groups.remove_member(scope, group.id, editor.id)
    assert {:error, _} = Transfer.apply(plan, editor)
    assert {:error, _} = Transfer.export([%{schema: Page, id: c.source.id, fields: ["blocks"]}], editor)
    assert blocks(c.target, c.user) == []
    editor |> Changeset.change(active: false) |> Repo.update!()
    assert {:error, _} = Transfer.preview(archive, %{}, editor)
  end

  test "retained region slots, nested content and footnote markers keep fresh consistent identities", c do
    slot =
      %Block{
        uid: Brando.Utils.generate_uid(),
        type: :slot,
        slot_kind: :region,
        slot_name: "unused_region",
        slot_module_set: "all",
        source: Page.Blocks,
        creator_id: c.user.id,
        parent_id: c.block.id
      }
      |> Repo.insert!()

    child =
      %Block{
        uid: Brando.Utils.generate_uid(),
        type: :module,
        module_id: c.module.id,
        source: Page.Blocks,
        creator_id: c.user.id,
        parent_id: slot.id,
        active: false,
        collapsed: true
      }
      |> Repo.insert!()

    ref = Repo.preload(c.block, :refs).refs |> hd()

    data =
      put_in(
        ref.data,
        [Access.key(:data), Access.key(:text)],
        ~s(<p>Retained <span data-footnote-uid="#{slot.uid}">1</span></p>)
      )

    ref |> Changeset.change(data: data) |> Repo.update!()
    plan = preview(c, export(c))
    assert plan.problems == []
    assert {:ok, _} = Transfer.apply(plan, c.user)
    [copied] = blocks(c.target, c.user)
    [copied_slot] = copied.children
    assert copied_slot.slot_name == "unused_region"
    assert copied_slot.uid != slot.uid
    assert hd(copied_slot.children).uid != child.uid
    refute hd(copied_slot.children).active
    assert hd(copied_slot.children).collapsed
    assert hd(copied.refs).data.data.text =~ copied_slot.uid
  end

  test "failed validation is visible in preview and cannot partially import other fields", c do
    archive = export(c)
    [field] = archive.bundle["fields"]
    archive = put_in(archive, [:bundle, "fields"], [put_in(field, ["blocks", Access.at(0), "type"], "slot")])
    plan = preview(c, archive)
    refute Transfer.applicable?(plan)
    assert {:error, _} = Transfer.apply(plan, c.user)
    assert Repo.aggregate(Receipt, :count) == 0
    assert blocks(c.target, c.user) == []
  end
end
