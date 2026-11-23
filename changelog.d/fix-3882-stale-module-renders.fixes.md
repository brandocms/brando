- A module that blocks in entries outside the trash use can no longer be moved to the trash: `Brando.Content.delete_module/2` returns `{:error, :module_in_use}`, and the module list's Delete names the entries using it, linked, instead of offering to delete.

- Restoring a module from the trash renders again the entries whose blocks use it, and so does trashing a site's customization of a library module.

- **Reset to shared** and accepting a library update on the shared library screen render again the environment's entries that use the entry.

- Restoring a module from the trash tells an open Release changes screen to plan again.

- A palette updated by a definitions import clears the cached containers that hold it, as a palette save does.

- **Reset to shared** and accepting a library update change the override and queue the renders together: one that fails leaves both as they were, and two at once no longer crash. For a palette they also update the site's palette CSS.

- Customizing, resetting and accepting a library update tell an open Release changes screen to plan again.

- Customizing a library palette that has colours no longer fails.
