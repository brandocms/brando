# syntax=docker/dockerfile:1

# -----------------------------------
# - stage: install
# - job: dependencies
# -----------------------------------

FROM --platform=linux/amd64 twined/fehn:4.2 as deps

ARG MIX_ENV=prod
ARG HEX_MIRROR_URL=https://repo.hex.pm

WORKDIR /opt/app

COPY config/ ./config
COPY mix.exs mix.lock /opt/app/
COPY VERSION /opt/app/

RUN mix deps.get --only $MIX_ENV


# -----------------------------------
# - stage: build
# - job: compile_deps
# -----------------------------------

FROM deps AS compile_deps
WORKDIR /opt/app

ARG MIX_ENV=prod
RUN mix deps.compile


# -----------------------------------
# - stage: build
# - job: compile_app
# -----------------------------------

FROM compile_deps AS compile_app
WORKDIR /opt/app

ARG MIX_ENV=prod

COPY lib/ ./lib
COPY priv/repo/ ./priv/repo
COPY priv/gettext/ ./priv/gettext
COPY rel ./rel

RUN mix compile


# -----------------------------------
# - stage: build
# - job: assets backend
# -----------------------------------

FROM node:24 AS assets_backend
WORKDIR /opt/app/assets/backend

# Keep in step with `packageManager` in assets/backend/package.json
RUN npm install --global pnpm@12.15.0

# The admin's CSS builds with the native EuropaCSS compiler. pnpm installs
# its executable for this image's platform from the lockfile's optional
# dependencies, so never pass --no-optional or copy node_modules in.

# The lockfile is the one `mix brando.assets.setup` writes; commit it.
# BrandoJS comes from npm, or from .yalc while you work on Brando itself
# (`mix brando.assets.setup --local`). The `[c]` makes the .yalc copy
# optional: BuildKit skips a COPY wildcard that matches nothing.
# pnpm-workspace.yaml holds pnpm's settings: the install scripts it allows,
# and the overrides
COPY assets/backend/package.json assets/backend/pnpm-lock.yaml assets/backend/pnpm-workspace.yaml ./
COPY assets/backend/.yal[c] ./.yalc/

RUN --mount=type=cache,target=/root/.local/share/pnpm/store,sharing=locked \
  pnpm install \
  --frozen-lockfile \
  --prefer-offline

COPY assets/backend/ ./

RUN pnpm build


# -----------------------------------
# - stage: build
# - job: assets frontend
# -----------------------------------

FROM node:24 AS assets_frontend
WORKDIR /opt/app/assets/frontend

# Keep in step with `packageManager` in assets/frontend/package.json
RUN npm install --global pnpm@12.15.0

# The site's CSS builds with the native EuropaCSS compiler too, installed
# from the lockfile's optional dependencies as in assets_backend.

# Jupiter comes from npm, or from .yalc if you install it from a checkout.
# The `[c]` makes the .yalc copy optional, as in assets_backend.
COPY assets/frontend/package.json assets/frontend/pnpm-lock.yaml assets/frontend/pnpm-workspace.yaml ./
COPY assets/frontend/.yal[c] ./.yalc/

# Use pnpm cache directory as a cache mount
# pnpm stores cache in ~/.local/share/pnpm/store by default
RUN --mount=type=cache,target=/root/.local/share/pnpm/store,sharing=locked \
  pnpm install \
  --frozen-lockfile \
  --prefer-offline

COPY assets/frontend/ ./

RUN pnpm build

# Vite writes hidden source maps and `mix brando.digest` deletes them, so they
# never ship. To upload them to Sentry first, commit an
# assets/frontend/.sentryclirc with your org and project, then build with
#   --secret id=sentry_auth_token,env=SENTRY_AUTH_TOKEN
# Without the secret this step does nothing. The CLI version is exact: the step
# runs with the token, so a new release is never fetched unreviewed.
ARG SENTRY_CLI_VERSION=3.8.2
RUN --mount=type=secret,id=sentry_auth_token \
  if [ -s /run/secrets/sentry_auth_token ]; then \
    export SENTRY_AUTH_TOKEN="$(cat /run/secrets/sentry_auth_token)" && \
    npx --yes @sentry/cli@${SENTRY_CLI_VERSION} sourcemaps inject ../../priv/static/assets && \
    npx --yes @sentry/cli@${SENTRY_CLI_VERSION} sourcemaps upload ../../priv/static/assets; \
  fi


# -----------------------------------
# - stage: build
# - job: digest
# -----------------------------------

FROM compile_deps AS digest
WORKDIR /opt/app

ARG MIX_ENV=prod

COPY --from=assets_backend /opt/app/priv ./priv
COPY --from=assets_frontend /opt/app/priv ./priv

RUN ls -al ./priv/static
RUN mix brando.digest


# -----------------------------------
# - stage: release
# - job: release
# -----------------------------------

FROM compile_app AS release

WORKDIR /opt/app

ARG MIX_ENV=prod

COPY --from=digest /opt/app/priv/static ./priv/static

RUN mix sentry.package_source_code
RUN mix release --overwrite
