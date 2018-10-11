#!/bin/sh

release_ctl eval --mfa "<%= application_module %>.ReleaseTasks.migrate/1" -- "$@"