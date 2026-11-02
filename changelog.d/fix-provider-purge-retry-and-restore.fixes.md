- A provider video whose provider could not answer the delete (a timeout, a connection error, a 5xx or a 429) is kept for the next purge, and with `delete_remote_on: :on_delete` asked again by a background job, rather than left at the provider for good.

- A deleted provider video is no longer restored from the trash while its environment has a live record of the same video; the trash names that record.
