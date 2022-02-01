#!/bin/bash

# All credit to u/skreak on Reddit

zpool status -x | grep -q 'all pools are healthy' || {
  zpool status | mail -s "NASOFDOOM: ZFS POOL WARNING" <redacted>@gmail.com

  WEBHOOK="https://discord.com/api/webhooks/<redacted>"
  curl \
    -XPOST \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"ZFS\", \"content\": \"NAS ZFS POOL WARNING: $(zpool status -x)\"}" \
    $WEBHOOK
}
