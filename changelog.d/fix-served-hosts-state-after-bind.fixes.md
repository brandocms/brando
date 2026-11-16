- A host bound on a multi-site installation shows **Checking** on the Environments screen as soon as it is saved, and its result within the lookup timeout, instead of nothing (or **Not served**) for up to a minute while the served hosts check waited on other hosts' lookups.

- A registry write on a multi-site installation no longer waits for the served hosts file to be read and written, and a server with many hosts waiting for DNS looks them up eight at a time, each with its full lookup timeout, instead of reporting hosts at the back as **Does not resolve**.
