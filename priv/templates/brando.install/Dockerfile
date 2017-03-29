FROM twined/fehn:1.3.4
# FROM twined/ando:1.0

MAINTAINER Twined Networks <mail@twined.net>

COPY . /opt/app
WORKDIR /opt/app

ENV MIX_ENV prod

RUN mix clean
RUN mix deps.clean --all
RUN mix deps.get
RUN mix deps.compile

# NPM
RUN cd assets && npm install
# YARN
# RUN cd assets && yarn --pure-lockfile
RUN cd assets && node_modules/.bin/brunch build -p

RUN mix phoenix.digest
RUN mix compile
RUN mix release --verbose
