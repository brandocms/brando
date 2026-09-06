# Navigation

A menu is addressed by **key and language**. Its ordered items contain link vars,
which can hold literal URLs or point to an entry's identifier. Use an identifier
for CMS pages so a later permalink change can be reflected in the menu.

This guide assumes a working admin, configured [content languages](i18n.md), and
a published page. Menu writes require an actor with navigation access in the
current site/environment.

## Build a main menu

Open **Configuration → Navigation**, create **Main navigation**, and set its key
to `main`, language to English, and status to published. Add an item with key
`about`. In its Link field, choose an entry link and select the About page. Use
**About us** as the link text, or leave the override blank to use the identifier
title. Save and reopen the menu to verify the selection and ordering survived.

For a seed or import, the equivalent literal-link menu is:

```elixir
{:ok, menu} = Brando.Navigation.create_menu(%{
  title: "Main navigation",
  key: "main",
  language: "en",
  status: :published,
  items: [%{
    key: "about",
    status: :published,
    sequence: 0,
    link: %{
      type: :link,
      key: "link",
      label: "Link",
      link_type: :url,
      link_text: "About us",
      value: "/about"
    }
  }]
}, current_user)
```

For an entry-backed link, replace `link_type: :url` and `value` with
`link_type: :identifier` and `identifier_id: identifier.id`. The identifier is a
`Brando.Content.Identifier` record, **not the page ID**. The admin picker handles
that distinction. `link_text: nil` lets the renderer use the identifier title; a non-nil
`link_text` overrides it. `link_target_blank: true` opens a new tab.

Create a separate `main` menu in Norwegian, pointing to the translated page.
Changing the menu's language does not translate its items or switch their
identifier targets. A missing translation should have a deliberate empty state;
there is no automatic fallback to the English menu.

## Load and render it

Place the navigation plug after locale and tenant resolution in your browser
pipeline:

```elixir
plug :put_locale
plug Brando.Plug.Tenant
plug Brando.Plug.Navigation, key: "main", as: :navigation
```

The keyword-list form is required. `plug Brando.Plug.Navigation, "main"` is an
obsolete API. Alternatively, `Brando.Navigation.get_menu("main", "en")` returns
`{:ok, menu}` or `{:error, {:menu, :not_found}}`.

Use the components in a HEEx layout:

```heex
<nav :if={@navigation && @navigation.status == :published} aria-label="Main">
  <ul>
    <Brando.HTML.menu :let={item} menu={@navigation}>
      <li>
        <Brando.HTML.menu_item :let={text} conn={@conn} item={item}>
          {text}
        </Brando.HTML.menu_item>
        <ul :if={item.children != []}>
          <li :for={child <- item.children} :if={child.status == :published}>
            <Brando.HTML.menu_item :let={text} conn={@conn} item={child}>
              {text}
            </Brando.HTML.menu_item>
          </li>
        </ul>
      </li>
    </Brando.HTML.menu>
  </ul>
</nav>
```

`menu` filters items to `:published` by default; the outer condition separately
checks the **menu** status. `menu_item` resolves the link and marks matching paths
with `data-link-active`. Use `splat={false}` if a link should match only its exact
path rather than descendant URLs. Style the active attribute and preserve a
visible keyboard focus indicator. The component supplies an ordinary anchor;
it does not implement a dropdown interaction for you.

## Nested items and ordering

Items support `parent_id` and `children`. The standard menu form edits the
menu's direct items; programmatic children can be created through
`Brando.Navigation.create_item/2` with a parent and a link:

```elixir
[parent] = menu.items

{:ok, _child} = Brando.Navigation.create_item(%{
  parent_id: parent.id,
  key: "team",
  sequence: 0,
  status: :published,
  link: %{
    type: :link, key: "link", label: "Link", link_type: :url,
    link_text: "Our team", value: "/about/team"
  }
}, current_user)
```

Do not also attach the child as a direct menu item through `menu_id`, or it can
appear at both levels. The menu preloads its items and one level of children,
including link identifiers. Deeper trees require an application-owned recursive
query and renderer. Set sequences deliberately in imports; the admin drag order
persists through the menu's sort parameter.

## Refresh and verify

Navigation context mutations refresh the navigation cache and request rendering
of block content that uses navigation. The cache is scoped to the current tenant
when tenancy is enabled. A direct `Repo` import bypasses these callbacks; after
it finishes, call `Brando.Cache.Navigation.set()` in the same environment and
rerender affected content through your normal content-rendering workflow.

Check the English and Norwegian routes, a menu with no published items, and a
missing menu. Rename the linked page's URI through its context, wait for the
identifier/rendering work, and verify the actual anchor destination. Missing or
unloaded identifiers cannot provide a usable link: preload `link: :identifier`
when rendering items from a custom query. Test tab navigation as well as clicks.
