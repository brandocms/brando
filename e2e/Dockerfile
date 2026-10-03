# syntax = docker/dockerfile:1

# -----------------------------------
# - stage: install
# - job: dependencies
# -----------------------------------

FROM --platform=linux/amd64 twined/fehn:3.8 as deps

ARG MIX_ENV=prod
ARG HEX_MIRROR_URL=https://repo.hex.pm

WORKDIR /opt/app

COPY config/ ./config
COPY mix.exs mix.lock /opt/app/

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

# Keep in step with `packageManager` in assets/backend/package.json
RUN npm install --global pnpm@10.32.1

# @brandocms/europacss fetches postcss-functions from GitHub, and the lockfile
# may record it as an SSH remote. The build has no SSH key; the repository is
# public, so fetch it over HTTPS.
RUN git config --global url."https://github.com/".insteadOf "git@github.com:"

# The backend links BrandoJS from this checkout (`link:../../../assets`),
# outside this build context. Pass it in as a named context:
#
#   docker build --build-context brandojs=../assets .
#
# It is placed where the link points, with its own dependencies installed,
# the same way CI builds the backend.
WORKDIR /opt/assets
COPY --from=brandojs package.json pnpm-lock.yaml ./
RUN --mount=type=cache,target=/root/.local/share/pnpm/store,sharing=locked \
      pnpm install \
      --frozen-lockfile \
      --prefer-offline
COPY --from=brandojs europa.config.js ./
COPY --from=brandojs src ./src
COPY --from=brandojs css ./css
COPY --from=brandojs vite ./vite

WORKDIR /opt/app/assets/backend
COPY assets/backend/package.json assets/backend/pnpm-lock.yaml ./
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
ENV YARN_CACHE_FOLDER ~/.yarn

COPY assets/frontend/package.json assets/frontend/yarn.lock ./
#COPY assets/frontend/.yalc ./.yalc
# Use the yarn cache directory as a cache mount
RUN --mount=type=cache,target=~/.yarn,sharing=locked \
      yarn \
      install \
      --pure-lockfile \
      --prefer-offline \
      --progress=false

COPY assets/frontend/ ./

RUN yarn build
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
RUN mix phx.digest


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