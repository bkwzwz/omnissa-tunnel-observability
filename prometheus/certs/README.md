# prometheus/certs/

Place your certificate team-issued PFX file here as `prometheus.pfx` before running
`setup.sh tunall` (only required when `PROMETHEUS_TLS_ENABLED=true` in `.env`).

`generate-config.sh` extracts `prometheus.crt`/`prometheus.key` from the PFX into this same
directory. None of the actual certificate/key files in this directory are committed to git
(see `.gitignore`) -- only this README exists to keep the directory present after a fresh clone.
