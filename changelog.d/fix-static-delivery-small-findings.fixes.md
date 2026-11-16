- A static build of a site without a sitemap says so in its log and in `mix brando.ssg`'s output: the application has no sitemap module, or it produced no entries.

- A failed static build's progress in the Publishing screen's build history says how many URLs it built and how many failed, instead of full progress.

- The build history's progress is labelled when the list stacks on a narrow screen.

- Setup and maintenance code can create a page, a fragment or any entry with a creator as `:system`, naming the creator with `creator:`: `Brando.Pages.create_page(params, :system, creator: user)`.
