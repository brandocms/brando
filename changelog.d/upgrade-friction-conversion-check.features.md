- **`mix brando.check.legacy_conversion` checks that the Villain → blocks
  upgrade kept a site's content.** While the Villain columns (`data`,
  `*_data`) are still there, it compares each entry's JSON with the blocks
  brando_103 to brando_133 made of it: the blocks at each level by type
  (root, container, multi module entries), each block's vars by key and
  whether a value was emptied, its refs by name, its table rows and
  datasource entries, and a fragment block's `fragment_id`. Findings read
  as a path, `pages #12 › block 3 (module "Values") › vars: heading
  missing`, and the task exits with status 1 when anything is missing
  (`--strict` also fails on content beyond Villain's). It runs in every
  environment, changes nothing, and leaves out what the migrations change
  on purpose, as its documentation lists. A multi module whose own vars an
  older brando_108 dropped is the kind of loss it finds.
