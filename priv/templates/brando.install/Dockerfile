## JAVASCRIPT FRONTEND AND BACKEND

FROM node:9 AS frontend_builder

COPY assets/frontend /opt/app/assets/frontend
WORKDIR /opt/app/assets/frontend
RUN yarn install --force --pure-lockfile
RUN yarn run build

FROM node:9 AS backend_builder

COPY assets/backend /opt/app/assets/backend
WORKDIR /opt/app/assets/backend
RUN yarn install --force --pure-lockfile
RUN yarn run build

## MAIN ELIXIR APPLICATION

FROM twined/fehn:1.9

LABEL maintainer="Twined Networks <mail@twined.net>"

WORKDIR /opt/app
ENV MIX_ENV prod

COPY lib lib
COPY test test
COPY config config
COPY rel rel
COPY priv/gettext priv/gettext
COPY priv/repo priv/repo

COPY mix.exs mix.lock ./
RUN mix deps.get
RUN mix deps.compile

RUN mix compile

COPY --from=frontend_builder /opt/app/priv/static/ priv/static/
COPY --from=backend_builder /opt/app/priv/static/ priv/static/

RUN mix phx.digest
RUN mix release
