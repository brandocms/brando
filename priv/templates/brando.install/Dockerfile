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

RUN cd assets && npm install
RUN cd assets && node_modules/.bin/brunch build -p assets/

RUN mix phoenix.digest
RUN mix compile
RUN mix release --verbosity=verbose
