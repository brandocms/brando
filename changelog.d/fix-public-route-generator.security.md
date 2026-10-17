- **Unpublished fragments no longer show on public pages** (#3230). The
  `partials` fragments the CMS pages, `BrandoWeb.FallbackController`'s error
  pages and `Brando.Plug.Fragment` read came from `Brando.Pages.get_fragments/1`
  in every status, and the site's layout rendered them, so a draft, pending or
  disabled `partials/footer` was public. `get_fragments/1,2` now give published
  fragments only (pass a `:status`, such as `status: :all`, for others), and an
  unpublished fragment renders nothing, interpolated in a template or through
  `Brando.Pages.render_fragment/1,2,3` or `fetch_fragment/2`, as a fragment
  block already did. A site whose public fragments are not published loses them:
  publish them in the admin. `Brando.Setup.Seeds` and the factory mixin's
  `fragment_factory` now create published fragments; a fragment inserted with
  no status, which the table's default makes published, is unpublished in the
  struct `insert` returns.
