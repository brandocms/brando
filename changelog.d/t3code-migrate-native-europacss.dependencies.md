- **No GitHub SSH dependency in the admin's packages** (#3187). BrandoJS, the
  generated backend and the E2E backend no longer depend on
  `@brandocms/europacss`, whose `postcss-functions` was pinned to an SSH Git
  remote. CI, the Dockerfiles and `scripts/worktree-setup` drop their
  `git@github.com:` → HTTPS URL rewrite.
