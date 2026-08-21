# Overview

This repo can be used as a recommendation for guidance on setting up observability for the Omnissa Tunnel Server, providing both telemetry (SNMP metrics) and logging (syslog).

## Architecture

![Tunnel Observability Architecture](./arch/TunnelObservability.png)

## Stack

| Component | Role |
|---|---|
| **Telegraf** | Polls Tunnel Server SNMP metrics |
| **Prometheus** | Stores and serves time-series metrics |
| **Grafana Alloy** | Receives syslog messages (TCP/UDP port 514) and forwards to Loki |
| **Loki** | Stores and indexes log data (7-day retention) |
| **Grafana** | Dashboards for metrics and logs (port 3000) |

## Tunnel Server

### Pre-reqs

* Tunnel configured on UEM Console. Follow the existing steps to enable SNMP (if using UAG).
* Tunnel Server deployed through UAG or container.
    * Tunnel Server container already exposes port 161 for SNMP stats. SNMP v2c is recommended.
* All connectivity should be working as expected and the Observability VM should be able to connect to the Tunnel Server.

### Set Up

* Deploy a Linux VM
    * Alma Linux is recommended. Download [here](https://almalinux.org/get-almalinux/).
    * Resource recommendation: 4 core, 16 GB RAM, 100 GB storage.
    * Ensure Docker and docker-compose are installed. Run `docker version` to confirm.
    * Start Docker: `systemctl start docker`
* Clone this repo onto the Linux VM, or zip and transfer it.
* Open [.env](./.env) and fill in the Linux VM IP and credentials:
```
TELEGRAF_HOST=<LINUX VM IP>

GRAFANA_PORT=3000
GRAFANA_URL=<LINUX VM IP>
GRAFANA_USER=<GRAFANA USERNAME>
GRAFANA_PASSWORD=<GRAFANA PASSWORD>
GRAFANA_PLUGINS_ENABLED=true
GRAFANA_PLUGINS=grafana-piechart-panel

PROMETHEUS_PORT=9090
PROMETHEUS_TLS_ENABLED=true
PROMETHEUS_USER=<PROMETHEUS USERNAME>
PROMETHEUS_PASSWORD=<PROMETHEUS PASSWORD>
```
* Open [telegraf/snmp.conf](./telegraf/snmp.conf) and fill in the Tunnel Server IPs:
```
[[inputs.snmp]]
  # Example: agents = [ "udp://1.2.3.4:161", "udp://3.4.5.6:161" ]
  agents = [ "udp://<Tunnel_Server_1>:161", "udp://<Tunnel_Server_2>:161", ... ]
```
* Run:
```
setup.sh tunall    # deploy all components
setup.sh clean     # tear down all containers
```

* Open a browser and navigate to `http://<linux-vm-ip>:3000` to view the Tunnel Stats dashboard.
    * To use your own Grafana instance, import the dashboard from [exported-dashboards](./exported-dashboards).

### Configuration (for Logging)

Tunnel Server sends logs via syslog to Grafana Alloy, which parses and forwards them to Loki.

* Configure the syslog destination (Linux VM IP) on the UEM Console. The syslog listener runs on **port 514** (TCP and UDP).
* For application (tunnel server) logs, additional KVP settings can be configured. Starting Tunnel Server version 26.03, use the below KVP to redirect tunnel application and reporter logs to syslog.
  - alert_log_mode 1
  - alert_log_rsyslog_host udp://192.168.1.1:514
  - audit_log_mode 1
  - audit_log_rsyslog_host udp://192.168.1.1:514

* Alloy parses three log message types from Tunnel Server:

| `msg_type` | Description | Key fields |
|---|---|---|
| `auditlog` | Configuration and audit events | `category`, `audit_type`, `server_ip` |
| `accesslog` | Device session connect/disconnect events | `event_type`, `status`, `user_name`, `device_name`, `port_number`, `device_app` |
| `alertlog` | Traffic flow alerts | `sub_type`, `user_name`, `hostname`, `port_number`, `device_app` |

### Configuration (for Telemetry)

* In UAG, enable SNMP following the guide [here](https://docs.omnissa.com/bundle/UnifiedAccessGatewayDeployandConfigureV2506/page/Systemconfiguration.html).
* SNMP v2c is recommended.
* Update `agents` in [telegraf/snmp.conf](./telegraf/snmp.conf) with the Tunnel Server IPs.

### Configuration (for Prometheus Remote Write)

Tunnel Server (vpnd/vpnreport) can push metrics directly to this stack's Prometheus via
remote-write, using the `prometheus_*` KVPs on the Tunnel Server. Everything on the
observability side is driven by [.env](./.env) -- no username/password/scheme is hardcoded.

* `PROMETHEUS_PORT`: host port Prometheus is published on (Tunnel Server connects to this).
* `PROMETHEUS_TLS_ENABLED`: `true` for HTTPS, `false` for plain HTTP.
* `PROMETHEUS_USER` / `PROMETHEUS_PASSWORD`: Basic Auth credentials required for both
  remote-write and the Grafana datasource.

If `PROMETHEUS_TLS_ENABLED=true`, place the PFX certificate issued by your certificate team
at `prometheus/certs/prometheus.pfx` before running `setup.sh tunall`. You will be prompted
for the PFX password on the terminal (only when the PFX is new/changed) so the PEM cert/key
pair can be extracted for Prometheus; the password itself is never written to disk.

`setup.sh tunall` runs [prometheus/generate-config.sh](./prometheus/generate-config.sh) to turn
these settings into `prometheus/web-config.yml` (TLS + bcrypt-hashed Basic Auth) before starting
the containers, and Grafana's Prometheus datasource picks up the same scheme/credentials via
Grafana's built-in `$__env{}` provisioning expansion.

Configure the Tunnel Server to match, using the `prometheus_*` KVPs (server-only, self-hosted
Basic Auth mode):
```
prometheus_enabled 1
prometheus_server_type 2
prometheus_server_remote_url https://<LINUX VM IP>:<PROMETHEUS_PORT>/api/v1/write
prometheus_port <PROMETHEUS_PORT>
prometheus_username <PROMETHEUS_USER>
prometheus_password <PROMETHEUS_PASSWORD>
```
Use `http://` in `prometheus_server_remote_url` instead if `PROMETHEUS_TLS_ENABLED=false`.

The default Grafana home dashboard (`TunnelStats.json`, provisioned automatically) only shows the
SNMP-based Tunnel Stats view, so customers are not overwhelmed by Prometheus's raw field-level
detail. A separate, much more detailed dashboard covering every `vpnserver_*` Prometheus metric,
[Tunnel Server - Prometheus Remote Write](./grafana/provisioning/dashboard/Tunnel%20Server%20-%20Prometheus%20Remote%20Write.json),
is **also provisioned automatically** (same mechanism as `TunnelStats.json`) and appears alongside
the Home dashboard in Grafana's dashboard list -- no manual import needed. That file under
`grafana/provisioning/dashboard/` is the single source of truth (it's what Grafana actually loads);
there is no separate exported copy to keep in sync.

### Tests

1. Enroll a device and try accessing any tunnelled resource.
2. You should start seeing stats and logs at `http://<linux-vm-ip>:3000`.


![Tunnel Logs](./docs/grafana2.png)
![Tunnel Stats](./docs/grafana.png)
