- Simultaneous MCP upload preparations share one pending limit per connection and check only that connection’s inventory after upgrade.
  Run `Brando.MCP.Uploads.sweep()` after the last node upgrades to include uploads staged by older nodes before the next nightly prune.
