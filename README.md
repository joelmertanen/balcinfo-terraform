# Terraformed influx + grafana backend for GCP

Ported my hobby project [balcinfo](https://github.com/joelmertanen/balcinfo)'s
backend to run on Grafana + InfluxDB.

Backend starts a compute instance, sets its DNS and external IP correctly.
The compute instance runs docker-compose's Grafana + InfluxDB on a shared network
disk with nginx'd reverse proxy (thanks Jareware!).

## Usage

Fill in the variables to `terraform.tfvars`.
```
terraform plan
terraform apply
```