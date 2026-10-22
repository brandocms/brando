- Unpublished fragments no longer show on public pages
  ([#3230](https://github.com/brandocms/brando/pull/3230)).
  A site whose public fragments are not published loses them: see Upgrading.
  `get_fragments/1,2` give an unpublished fragment with no content, also with `status: :published`;
  pass `status: :all` for fragments as stored.
  An entry that embeds a fragment through `{% fragment %}` or a block template shows it published
  or unpublished from its next save.
  `fragment_factory` creates published fragments; one inserted with no status is unpublished in the
  struct `insert` returns, so pass `status: :published` in tests that render it.
