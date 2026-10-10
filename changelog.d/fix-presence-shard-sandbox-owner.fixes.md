- **A failed users lookup no longer takes admin presence down**. Presence
  looks up the users behind each join and leave in a task the tracker
  watches; when that query failed (a pool timeout, say), the tracker crashed
  and forgot the admin sessions it held, so who is online and who is in
  which field went missing until the editors' pages reconnected. The lookup
  now logs the failure, and the sessions it could not look up are kept
  without their user details.
