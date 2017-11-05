## v2.0.0-alpha.0 (XX-XX-XXXX)

* Backwards incompatible changes

  - `render_fragment` has been renamed to `fetch_fragment`.
    It is recommended to use `get_page_fragments/1` by `parent_key` to fetch all relevant fragments and display them
    with `render_fragment/2`

  - `brando_pages` has been incorporated into `brando` core. Remove `brando_pages` from your deps and application list

## v1.0.0, see own v1 branch
