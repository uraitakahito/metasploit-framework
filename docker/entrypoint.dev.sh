#!/bin/bash
# Development entrypoint script

MSF_USER=msf
MSF_GROUP=msf
TMP=${MSF_UID:=1000}
TMP=${MSF_GID:=1000}

# Development mode: run as root for easier debugging
if [ "$DEV_MODE" = "true" ] || [ "$MSF_UID" -eq "0" ]; then
  exec "$@"
else
  # if the users group already exists, create a random GID, otherwise reuse it
  if ! getent group $MSF_GID > /dev/null; then
    addgroup -g $MSF_GID $MSF_GROUP
  else
    addgroup $MSF_GROUP
  fi

  # check if user id already exists
  if ! getent passwd $MSF_UID > /dev/null; then
    adduser -u $MSF_UID -D $MSF_USER -g $MSF_USER -G $MSF_GROUP $MSF_USER
    # add user to metasploit group so it can read the source
    addgroup $MSF_USER $METASPLOIT_GROUP
    su-exec $MSF_USER "$@"
  # fall back to root exec if the user id already exists
  else
    exec "$@"
  fi
fi
