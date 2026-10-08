defmodule Brando.SequenceLoadOrderTest do
  # Rows written without a sequence all have 0. Ordered by sequence alone,
  # Postgres returns such ties in physical order, which changes whenever a row
  # is rewritten (an update, or space other transactions freed); that is what
  # made set_field_test.exs flaky (see block_load_order_test.exs). `:id`
  # breaks the tie everywhere these rows are loaded. Each test writes two rows
  # with the same sequence, rewrites the first so it moves behind the second
  # on disk, and checks they still load in the order they were written.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query

  alias Brando.Factory

  defp tie(rows), do: for(row <- rows, do: set_sequence(row, 0))

  defp set_sequence(%{__struct__: schema, id: id}, sequence) do
    Repo.update_all(from(r in schema, where: r.id == ^id), set: [sequence: sequence])
  end

  # Writes the row again in place, which moves it on disk.
  defp rewrite(%{__struct__: schema, id: id}) do
    Repo.query!(~s[UPDATE "#{schema.__schema__(:source)}" SET sequence = sequence WHERE id = $1], [id])
  end

  defp ids(rows), do: Enum.map(rows, & &1.id)

  test "a module's refs and vars" do
    user = Factory.insert(:random_user)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Two of each"},
          namespace: %{"en" => "Content"},
          help_text: %{"en" => "Help"},
          code: "{% ref refs.first %}{% ref refs.second %}",
          refs: [
            %{name: "first", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "One"}}},
            %{name: "second", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Two"}}}
          ],
          vars: [
            %{key: "first", type: "string", label: %{"en" => "First"}},
            %{key: "second", type: "string", label: %{"en" => "Second"}}
          ]
        ),
        user
      )

    module = Repo.preload(module, [:refs, :vars], force: true)
    [ref, _] = module.refs
    [var, _] = module.vars
    tie(module.refs ++ module.vars)
    rewrite(ref)
    rewrite(var)

    reloaded = Repo.preload(module, [:refs, :vars], force: true)
    assert Enum.map(reloaded.refs, & &1.name) == ["first", "second"]
    assert Enum.map(reloaded.vars, & &1.key) == ["first", "second"]
  end

  test "a menu's items" do
    user = Factory.insert(:random_user)

    item = fn key ->
      %Brando.Navigation.Item{
        key: key,
        status: :published,
        creator_id: user.id,
        link: %Brando.Content.Var{
          type: :link,
          link_type: :url,
          creator_id: user.id,
          link_text: key,
          placement: :content,
          label: "Link",
          key: "link",
          value: "https://#{key}.example"
        }
      }
    end

    menu =
      Repo.insert!(%Brando.Navigation.Menu{
        creator_id: user.id,
        key: "order",
        language: :en,
        title: "Order",
        status: :published,
        items: [item.("first"), item.("second")]
      })

    [first, _] = menu.items
    tie(menu.items)
    rewrite(first)

    assert menu |> Repo.preload(:items, force: true) |> Map.get(:items) |> Enum.map(& &1.key) == ["first", "second"]
  end

  test "a form's fields" do
    user = Factory.insert(:random_user)

    {:ok, form} =
      Brando.Forms.create_form(
        %{
          "title" => "Order",
          "key" => "order",
          "language" => "en",
          "status" => "published",
          "fields" => [
            %{"key" => "first", "type" => "text", "label" => "First"},
            %{"key" => "second", "type" => "text", "label" => "Second"}
          ]
        },
        user
      )

    form = Repo.preload(form, :fields, force: true)
    [first, _] = form.fields
    tie(form.fields)
    rewrite(first)

    assert form |> Repo.preload(:fields, force: true) |> Map.get(:fields) |> Enum.map(& &1.key) == ["first", "second"]
  end

  test "a global set's globals" do
    user = Factory.insert(:random_user)

    {:ok, set} =
      Brando.Sites.create_global_set(
        %{
          "label" => "Order",
          "key" => "order",
          "language" => "en",
          "vars" => [
            %{"type" => "string", "key" => "first", "label" => %{"en" => "First"}, "placement" => "content"},
            %{"type" => "string", "key" => "second", "label" => %{"en" => "Second"}, "placement" => "content"}
          ]
        },
        user
      )

    set = Repo.preload(set, :vars, force: true)
    [first, _] = set.vars
    tie(set.vars)
    rewrite(first)

    assert set |> Repo.preload(:vars, force: true) |> Map.get(:vars) |> Enum.map(& &1.key) == ["first", "second"]
  end

  test "an entry's blocks, through the relation and the block preloads" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    alias Brando.Pages.Page

    joins =
      for uid <- ~w(firstblock000000000001 secondblock00000000002) do
        block = Repo.insert!(%Brando.Content.Block{uid: uid, type: :module, source: to_string(Page.Blocks)})
        Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
      end

    rewrite(hd(joins))

    by_relation = page |> Repo.preload(:entry_blocks, force: true) |> Map.get(:entry_blocks)
    assert ids(by_relation) == ids(joins)

    by_block_preloads = page |> Repo.preload(Brando.Content.BlockPreloads.for_schema(Page), force: true)
    assert ids(by_block_preloads.entry_blocks) == ids(joins)
  end

  test "a gallery's objects" do
    gallery = Factory.insert(:gallery)

    objects =
      for _ <- 1..2 do
        image = Factory.insert(:image)
        Repo.insert!(%Brando.Galleries.GalleryObject{gallery_id: gallery.id, image_id: image.id, sequence: 0})
      end

    rewrite(hd(objects))

    loaded = Repo.one!(from(g in Brando.Galleries.Gallery.preloads_for(), where: g.id == ^gallery.id))
    assert ids(loaded.gallery_objects) == ids(objects)
  end

  test "fragments under one parent" do
    user = Factory.insert(:random_user)

    fragments =
      for key <- ~w(first second),
          do: Factory.insert(:fragment, parent_key: "order", key: key, language: :en, sequence: 0, creator: user)

    rewrite(hd(fragments))

    {:ok, listed} = Brando.Pages.list_fragments(%{filter: %{parent_key: "order"}})
    assert ids(listed) == ids(fragments)

    {:ok, rendered} = Brando.Pages.FragmentQuery.list_for_rendering()
    assert rendered |> Enum.filter(&(&1.parent_key == "order")) |> ids() == ids(fragments)
  end
end
