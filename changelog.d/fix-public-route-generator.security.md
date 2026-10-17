- **Unpublished fragments no longer show on public pages** (#3230). The
  `partials` fragments the CMS pages, `BrandoWeb.FallbackController`'s error
  pages and `Brando.Plug.Fragment` read came from `Brando.Pages.get_fragments/1`
  in every status, and the site's layout rendered them, so a draft, pending or
  disabled `partials/footer` was public. `get_fragments/1,2` now give an
  unpublished fragment under its key with no content (`rendered_blocks: nil`),
  so every way a template reads it renders nothing, and the page does not fail
  on a missing key (pass a `:status`, such as `status: :all`, for fragments as
  stored). An unpublished fragment also renders nothing interpolated in a
  template, through `<Brando.HTML.fragment fragment={…} />`, the
  `{% fragment %}` tag, `Brando.Pages.render_fragment/1,2,3` or
  `fetch_fragment/2`, as a fragment block already did; a struct from
  `Brando.Pages.get_fragment/2` rendered with the component showed its draft.
  The `{% fragment parent key language %}` tag read a fragment's `html`, which
  it has not had since 0.54, and raised; it renders the fragment. A key missing
  from a partials map renders nothing through the component, which raised
  `KeyError`. A site whose public fragments are not published loses them:
  see Upgrading. `Brando.Setup.Seeds` and the factory mixin's
  `fragment_factory` now create published fragments; a fragment inserted with
  no status, which the table's default makes published, is unpublished in the
  struct `insert` returns.
