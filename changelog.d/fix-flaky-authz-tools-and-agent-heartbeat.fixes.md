- **An editor who activates a revision stays in the entry's edit session.**
  Activating a revision takes the block fields out of the form and renders
  them again a moment later, to mount them from the written entry. LiveView
  keeps a component that is rendered again before the browser has confirmed
  it gone, state and all, and a block field kept that way after previewing
  the revision stayed detached from the edit session: the editor no longer
  saw the others' changes, nor they the editor's. A slow connection could
  do it; a loaded test run did. A block field that comes back now starts
  over from the entry's rows and joins the session.
