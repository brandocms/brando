- **`mix brando.gen.backend --upgrade` moves the Dockerfile's `assets_frontend`
  stage to the admin's Node.** It used to only note that the stage still built
  on `node:16`. When `assets/frontend/package.json` sets no `engines.node`, or
  a range that allows the `assets_backend` stage's Node major, the stage's
  `FROM node:<n>` now names that major (`node:16` → `node:22`, keeping a
  variant such as `-alpine`). When the range excludes it, or cannot be read,
  the stage is left alone and the notice says which.
