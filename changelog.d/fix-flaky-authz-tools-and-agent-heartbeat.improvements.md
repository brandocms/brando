- **The admin menu reads permissions once per scope.** With group
  authorization, building the sidebar menu read the user and their groups
  for every item it checked: 65 queries for the default menu. Every open
  admin page builds it again when any user or group changes, so one change
  sent a burst of queries per open page. It now reads each scope once,
  7 queries in all (`Brando.Authorization.with_snapshots/1`).
