FROM twined/fehn:1.3.5

MAINTAINER Twined Networks <mail@twined.net>

COPY . /opt/app
WORKDIR /opt/app

ENV MIX_ENV prod

RUN mix clean
RUN mix deps.clean --all
RUN mix deps.get
RUN mix deps.compile

COPY assets/frontend/package.json assets/frontend/yarn.lock /opt/app/assets/frontend/
COPY assets/backend/package.json assets/backend/yarn.lock /opt/app/assets/backend/

RUN cd assets/backend && yarn install --force --pure-lockfile
RUN cd assets/frontend && yarn install --force --pure-lockfile
RUN cd assets/backend && yarn build
RUN cd assets/frontend && yarn build

RUN mix phx.digest
RUN mix compile
RUN mix release
