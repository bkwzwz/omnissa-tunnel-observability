#! /bin/bash

if [ $# -ne 1 ]; then
   echo "Run setup.sh with:
     tunall: if all tunnel observability components need to run
     clean: clean up all containers"
   exit 1
fi

if id -u "loki" >/dev/null 2>&1; then
    echo 'loki user exists'
else
    echo 'loki user missing'
    useradd loki
fi


### Ensure Loki data directories exist and are owned by UID 10001
### (the user Loki runs as inside its container)
### Uncomment below to setup permissions for loki folders
# sudo mkdir -p /home/loki/wal /home/loki/tsdb-index /home/loki/tsdb-cache \
#         /home/loki/chunks /home/loki/shipper-compactor \
#         /home/loki/rules /home/loki/rules-temp
# sudo chown -R 10001:10001 /home/loki

case "$1" in
  "tunall")
       ./prometheus/generate-config.sh
       docker compose -f docker-compose.yml up --build --force-recreate -d; shift;;
  "clean")
       docker compose down --remove-orphans; shift;;
esac
