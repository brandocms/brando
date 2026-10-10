- **A cached query no longer keeps an entry as it was before a save.** A
  save inside a transaction (every save from the admin with group
  authorization) cleared the entry's cached queries before the save was
  committed, so a page read by a visitor in between cached the old content
  again, for as long as the query caches (15 minutes by default). Cached
  queries are now cleared again once the save has committed.

- **One background job per video and per SEO suggestion.** A Vimeo upload
  that took more than a minute got a second status check that polled Vimeo
  beside the first until the video was ready; fetching video details twice
  while the first lookup still waited looked each video up twice; and two
  runs that queued the same meta description or alt text asked the AI for
  it twice. Each now has one waiting job at a time.

- **Two search index rebuilds asked for at once queue one.** Without
  tenancy, a rebuild's job carried nothing for its uniqueness to compare,
  so two editors starting a rebuild from Utilities at the same moment
  rebuilt the index twice.
