- Deleting a page no longer leaves its fragments on the trashed page, hidden in the admin but still on the site: the delete dialog lists them and moves them to another page (the page above, preselected) or deletes them with the page, restored with it. `Brando.Pages.delete_page/2` and a bulk delete move them to the page above, or the homepage in its language; pass `fragments:` to `delete_page/3` for another choice.

- The pages listing shows fragments whose page is in the trash or gone, or that never had one, under "Fragments without a page", and `mix brando.doctor` warns about those on a trashed or missing page.
  Run `mix brando.doctor` to find fragments left by pages deleted before this release, then give each a page under Pages → Fragments without a page.
