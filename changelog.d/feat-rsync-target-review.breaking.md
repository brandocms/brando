- An rsync deploy deletes on its target only what Brando uploaded or an admin confirmed, never a path on the site's keep list (`.well-known/` and `cgi-bin/` unless changed), and is refused for a target nobody has reviewed.
  For each site that deploys with rsync, open Publishing, press Test connection, tick what to keep among the entries it lists, then press Confirm; deploy again afterwards.
