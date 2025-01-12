#!/bin/zsh
set -e

# Default test command
TEST_COMMAND="test"

# Check if --ui was passed as the first argument
if [ "$1" = "--ui" ]; then
  TEST_COMMAND="test:ui"
fi

# Run the Mix tasks and then execute the Playwright tests
MIX_ENV=e2e mix do ecto.drop, ecto.create, ecto.migrate, run priv/repo/e2e_seeds.exs && cd e2e/playwright && yarn $TEST_COMMAND