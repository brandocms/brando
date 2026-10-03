# syntax = docker/dockerfile:1.0-experimental

# -----------------------------------
# - stage: install
# - job: dependencies
# -----------------------------------

FROM --platform=linux/amd64 twined/fehn:4.0 as deps

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

FROM node:22 AS assets_backend
WORKDIR /opt/app/assets/backend

# Keep in step with `packageManager` in assets/backend/package.json
RUN npm install --global pnpm@10.32.1

# @brandocms/europacss fetches postcss-functions from GitHub, and the lockfile
# may record it as an SSH remote. The build has no SSH key; the repository is
# public, so fetch it over HTTPS.
RUN git config --global url."https://github.com/".insteadOf "git@github.com:"

# The lockfile is the one `mix brando.assets.setup` writes; commit it.
# BrandoJS itself is installed from .yalc.
COPY assets/backend/package.json assets/backend/pnpm-lock.yaml ./
COPY assets/backend/.yalc ./.yalc

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

FROM node:22 AS assets_frontend
WORKDIR /opt/app/assets/frontend

# pnpm uses a different cache structure
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# Install pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

COPY assets/frontend/package.json assets/frontend/pnpm-lock.yaml ./
COPY assets/frontend/.yalc ./.yalc

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
# Without the secret this step does nothing.
RUN --mount=type=secret,id=sentry_auth_token \
  if [ -s /run/secrets/sentry_auth_token ]; then \
    export SENTRY_AUTH_TOKEN="$(cat /run/secrets/sentry_auth_token)" && \
    npx --yes @sentry/cli@3 sourcemaps inject ../../priv/static/assets && \
    npx --yes @sentry/cli@3 sourcemaps upload ../../priv/static/assets; \
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