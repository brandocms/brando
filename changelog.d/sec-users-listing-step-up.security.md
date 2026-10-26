- Deleting users in bulk and restoring a deleted user from the users listing now ask for the password, a code or a passkey when the session has not confirmed lately, like the other user actions; deleting one user always goes through the transfer dialog.

- A listing can name events that ask again with the `step_up` option of `use BrandoAdmin.LiveView.Listing`, including the listing's own delete and restore events.
