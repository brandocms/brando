- Simultaneous MCP upload preparations share one pending limit per connection and check only that connection’s inventory after upgrade.
  After a rolling upgrade, `Brando.MCP.Uploads.sweep/0` counts uploads staged by older nodes at the next nightly prune or when run manually.
