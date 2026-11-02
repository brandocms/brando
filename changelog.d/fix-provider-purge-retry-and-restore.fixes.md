- A provider video whose provider could not answer the delete (a timeout, a connection error, a 5xx or a 429) is kept for the next purge, as are that provider's other videos the same purge would have asked it about, and with `delete_remote_on: :on_delete` asked again by a background job, rather than left at the provider for good.

- A deleted provider video is no longer restored from the trash while its environment has a live record of the same video; the trash names that record.

- Restoring a video from the trash after the purge deleted it says it could not, rather than crashing the page.
