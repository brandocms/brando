FROM ubuntu:14.04

MAINTAINER Twined Networks <mail@twined.net>

# Elixir requires UTF-8
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Install build reqs
RUN apt-get update && apt-get upgrade -y && apt-get install -y curl wget git make build-essential openssl libssl-dev

# For some reason, installing Elixir tries to remove this file
# and if it doesn't exist, Elixir won't install. So, we create it.
# Thanks Daniel Berkompas for this tip.
# http://blog.danielberkompas.com
RUN touch /etc/init.d/couchdb

# Download and install Erlang repo
RUN wget http://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb \
 && dpkg -i erlang-solutions_1.0_all.deb \
 && apt-get update

# Install Elixir
RUN apt-get install -y elixir erlang-dev erlang-parsetools && rm erlang-solutions_1.0_all.deb

# Install Node.js (>= 5.0.0) and NPM in order to satisfy brunch.io dependencies
# See http://www.phoenixframework.org/docs/installation#section-node-js-5-0-0-
RUN curl -sL https://deb.nodesource.com/setup_5.x | sudo -E bash - && apt-get install -y nodejs

# Install local Elixir hex and rebar
RUN /usr/local/bin/mix local.hex --force
RUN /usr/local/bin/mix local.rebar --force

# Add files to container
ADD . /app
WORKDIR /app

# Set prod environment
ENV MIX_ENV prod

# Fetch and compile deps
RUN mix deps.get
RUN mix deps.compile

# Install node packages
RUN npm install

# Build static files
RUN node_modules/.bin/brunch build -p

# Create digest
RUN mix phoenix.digest

# Compile project
RUN mix compile

# Create a release
RUN mix release --verbosity=verbose
