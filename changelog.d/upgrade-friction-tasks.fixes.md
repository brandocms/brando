- **`mix brando.migrate54` moves Villain editors to form-level `blocks`.**
  It replaced `attribute :data, :villain` with a `:blocks` relation but left
  `input :data, :blocks` in its fieldset, which then referenced an unknown
  field. The input now becomes `blocks :blocks` on the form, with its
  options, and a fieldset or tab it leaves empty is removed. Rerunning the
  task moves an input an earlier run left behind.
