# Creating content from code

<!-- llms-description: Seed scripts, demo content, imports and data migrations with Brando.Content.Seed: blocks with images and galleries, entries, menus, identity and globals, with several sites. -->

Seed scripts, demo content, an import of a design's content, a data
migration: content made by code rather than by an editor. `Brando.Content.Seed`
builds it from modules, files and plain values, and saves it through the
same contexts as the admin. The user a script acts as needs the rights an
editor would need, and identifiers, revisions, the activity log, rendering
and cache eviction happen as when an editor saves.

<!-- usage-rules:start topic="seeding" -->
## A seed script

This script creates a published page, Lobby, with one block of the module
whose uid is `image-row` (a picture ref, `picture`, and a text ref,
`caption`), unless the page is there already. The image is uploaded from a
file in the application:

<!-- seeding-example -->
```elixir
# priv/repo/seeds/lobby.exs, run with: mix run priv/repo/seeds/lobby.exs
alias Brando.Content.Seed

{:ok, user} = Brando.Users.get_user(%{matches: %{email: "admin@example.com"}})

case Brando.Pages.get_page(%{matches: %{uri: "lobby", language: "en"}}) do
  {:ok, page} ->
    page

  {:error, _} ->
    {:ok, image} = Seed.upload_image("priv/seeds/lobby.jpg", user, alt: "The lobby")

    block =
      Seed.block("image-row", user,
        refs: %{"picture" => image, "caption" => "<p>Open from eight.</p>"}
      )

    {:ok, page} =
      Seed.create_entry(
        Brando.Pages.Page,
        %{title: "Lobby", uri: "lobby", language: "en", template: "default.html", status: :published},
        user,
        blocks: [block]
      )

    page
end
```

Brando's test suite runs this example as it is written here
(`test/brando/content/seed_guide_test.exs` reads it from this guide), twice,
so it cannot drift from the code, and a second run finds the page.

## Blocks

`Seed.block/3` builds a block of a module as the block editor inserts it,
with the module's default content. Name the module by the `uid` of its
[module definition](module_definitions.md), or pass the module or its id.
Give refs and vars by name:

```elixir
Seed.block("teaser", user,
  refs: %{
    "title" => "Lobby",
    "body" => "<p>Open from eight.</p>",
    "cover" => "priv/seeds/lobby.jpg",
    "slides" => ["priv/seeds/one.jpg", "priv/seeds/two.jpg"],
    "note" => false
  },
  vars: %{"wide" => true, "label" => "New", "link" => about_page}
)
```

A ref takes:

- a string: the text of a text or header ref, or, for a picture, video or
  media ref, the path of a file to upload;
- an image, video or file struct;
- a list of images, videos or paths for a gallery ref, which makes the
  block a new gallery of them; a saved `Brando.Galleries.Gallery` is used
  as it is;
- a map of the ref's data fields, such as `%{text: "Lobby", level: 2}` for
  a header;
- `false`, to switch the ref off.

Never give a picture ref its data (`PictureBlock` fields): the image goes in
as a struct or a path, and the block renders it. A media ref, which an
editor fills with a picture, a video or a gallery, takes the type of what it
is given, with the module's template for that type.

A var takes a string, a boolean, an image, video or file (or a path, for an
image or video var), a list of images or videos for a gallery var, and for a
link var a URL or an entry. A name the module does not have raises, and the
message lists the names it has.

Files are uploaded as the user. `Seed.upload_image/3` returns the image the
library already has when it has the same bytes, so a script can run again;
`Seed.upload_video/2` stores a file each time. Image sizes are made in the
background, and the entries that show the image are rendered again when
they are done: a `mix run` script that ends first leaves the work queued,
for the server's next start.

## Entries

`Seed.create_entry/4` creates an entry of any blueprint through its
context's `create_*` function, rendered, with its blocks. Params are what
the admin form sends: a language is `"en"` or `:en`. Blocks go to the first
block field, or by field name:

```elixir
{:ok, footer} =
  Seed.create_entry(
    Brando.Pages.Fragment,
    %{title: "Footer", parent_key: "partials", key: "footer", language: "en", status: :published},
    user,
    blocks: [blocks: [Seed.block("footer", user, refs: %{"text" => "<p>Acme</p>"})]]
  )
```

`Seed.add_blocks/4` adds blocks to an entry that exists, after its blocks or
at `at:`, and saves it through `update_*`. Both return `{:ok, entry}`, or
`{:error, changeset}` or `{:error, :forbidden}`, as the context does.

## Menus, identity and globals

Menus are created with `Brando.Navigation.create_menu/2`;
`Seed.menu_item/3` gives the params of an item that links to a URL or an
entry:

```elixir
{:ok, _menu} =
  Brando.Navigation.create_menu(
    %{
      title: "Main menu",
      key: "main",
      language: "en",
      status: :published,
      items: [Seed.menu_item("Home", "/"), Seed.menu_item(nil, lobby)]
    },
    user
  )
```

An entry's item links through the entry's identifier, and shows the entry's
title when its text is `nil`. Delete an item with
`Brando.Navigation.delete_item/2`, which takes the item or its id, as every
generated `delete_*` function does.

The site's identity is changed through `Brando.Sites`, and a global set's
values by var key with `Seed.put_globals/4`:

```elixir
{:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})
{:ok, _identity} = Brando.Sites.update_identity(identity, %{name: "Acme", title: "Acme"}, user)

{:ok, _set} = Seed.put_globals("contact", "en", %{"email" => "hi@acme.test", "open" => true}, user)
```

## Rendering and caches

What these functions save is rendered and evicted from the caches, as an
editor's save is. `Seed.render/1` renders an entry again, after changing
what its blocks show from outside them. A write that does not go through a
context (`Repo.update_all/3`, a migration) neither renders nor evicts: call
`Brando.Cache.clear_content/1`, then `Seed.render/1` for each entry it
changed. [Pages](pages.md) says what a script in its own VM can clear.

## Checking what exists

To make a script safe to run again, look for what it creates first: with
the context's `get_*` function, or with your application's Repo
(`MyApp.Repo.exists?/1`). `Brando.Repo` has no `exists?/1`: it is a wrapper
for queries Brando makes, not your Repo.

## Several sites

With `tenancy_mode: :multi`, content belongs to a site's environment. Run
the seed script inside one, here from another script:

```elixir
prefix = Brando.Tenant.prefix("acme", "production")

Brando.Tenant.with_prefix(prefix, fn ->
  Code.eval_file("priv/repo/seeds/lobby.exs")
end)
```

Everything inside, uploads included, reads and writes that environment, and
the user needs rights in it. Outside one, a query on a site's table raises
`Brando.Exception.MissingTenantError`.
<!-- usage-rules:end -->

## In tests

`Brando.Test.build_block/2` and `Brando.Test.insert_block/3` are built on
`Brando.Content.Seed`, and take the same `refs:` and `vars:`; see
[Testing](testing.md).
