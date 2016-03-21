FROM twined/fehn:latest

MAINTAINER Twined Networks <mail@twined.net>

COPY . /app
WORKDIR /app

ENV MIX_ENV prod

RUN mix clean
RUN mix deps.clean --all
RUN mix deps.get
RUN mix deps.compile

RUN npm install
RUN node_modules/.bin/brunch build -p

RUN mix phoenix.digest
RUN mix compile
RUN mix release --verbosity=verbose
