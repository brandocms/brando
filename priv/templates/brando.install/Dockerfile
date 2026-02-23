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
ENV YARN_CACHE_FOLDER ~/.yarn

# COPY --from=deps /opt/app/deps /opt/app/deps/
COPY assets/backend/package.json assets/backend/yarn.lock ./
COPY assets/backend/.yalc ./.yalc
# Use the yarn cache directory as a cache mount
RUN --mount=type=cache,target=~/.yarn,sharing=locked \
  yarn \
  install \
  --pure-lockfile \
  --prefer-offline \
  --progress=false

COPY assets/backend/ ./

RUN yarn build


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
RUN mkdir -p ../../priv/static/assets/__srcmaps && \
  mv ../../priv/static/assets/*.map ../../priv/static/assets/__srcmaps/


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