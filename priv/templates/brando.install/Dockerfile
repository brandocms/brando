FROM twined/fehn:1.3.1

MAINTAINER Twined Networks <mail@twined.net>

COPY . /app
WORKDIR /app

ENV MIX_ENV prod

RUN mix clean
RUN mix deps.clean --all
RUN mix deps.get
RUN mix deps.compile

COPY package.json yarn.lock /app/
RUN yarn --pure-lockfile
RUN node_modules/.bin/brunch build -p

RUN mix phoenix.digest
RUN mix compile
RUN mix release --verbosity=verbose
