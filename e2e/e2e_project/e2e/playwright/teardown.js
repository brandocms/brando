// Teardown is not needed - Playwright kills the server when tests complete.
// The /halt endpoint was copied from Phoenix LiveView's e2e setup but requires
// an e2e_helper.exs script to register a process that handles the shutdown.
module.exports = async () => {}
