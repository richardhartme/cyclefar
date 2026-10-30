# CycleFar AWS infrastructure (Terraform)

Terraform configuration for a small, single-server production environment. It provisions AWS infrastructure only; it doesn't build or deploy the app. A [CloudFormation alternative](cloudformation/README.md) exists: use one tool per environment, never both.

## What it creates

- A VPC with one public application subnet, an Internet Gateway and a public route.
- Two private database subnets in separate Availability Zones (required by RDS), with no NAT or Internet route.
- One Ubuntu 24.04 LTS EC2 instance with an Elastic IP, SSH access and an SSM-enabled instance profile.
- Application and database security groups; the database accepts PostgreSQL (5432) only from the application.
- One encrypted, private PostgreSQL RDS instance with seven days of automated backups.
- Optionally, a Route 53 `A` record for `cyclefar.com` in an existing hosted zone.

Deliberately absent: ECS, Kubernetes, load balancers, autoscaling, Redis, CloudFront, NAT gateways and deployment resources.

## Prerequisites

- Terraform 1.6 or newer, below 2.0.
- An AWS identity allowed to manage VPC, EC2, Elastic IPs, IAM instance profiles, RDS and (if used) Route 53 records. Credentials come from the normal provider chain; never put access keys in Terraform files. For example:

  ```sh
  aws configure sso --profile cyclefar
  aws sso login --profile cyclefar
  export AWS_PROFILE=cyclefar
  aws sts get-caller-identity
  ```

- An SSH key pair, as an existing EC2 key-pair name or an OpenSSH public key.
- An existing hosted zone, only if Terraform should create the DNS record.

## Configure

```sh
cd infra
cp terraform.tfvars.example terraform.tfvars   # ignored by Git
```

- Set exactly one of `ssh_key_name` or `ssh_public_key`, and set `ssh_allowed_cidrs` to your trusted IP range (an empty list is rejected).
- Leave `database_password` as `null` to generate one. It's marked sensitive but still stored in Terraform state, so keep state private and out of Git. To supply your own: `export TF_VAR_database_password='...'`.
- `route53_zone_id` is optional. Terraform never creates or discovers a zone; given an existing, delegated zone ID, it points `domain_name` at the Elastic IP.

RDS database names can't contain underscores, so the initial database is `cyclefarproduction` and can stay unused. Rails uses `cycle_far_production` plus `_cache`, `_queue` and `_cable` databases, which `bin/rails db:prepare` (also run by the Docker entrypoint) creates with the RDS master user.

## Workflow

From `infra/`:

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply     # only after reviewing the plan; nothing in the repo applies automatically
```

`terraform destroy` takes a final RDS snapshot by default (which keeps costing storage). Set `rds_skip_final_snapshot = true` only to discard the database on purpose.

## Costs

EC2 and EBS, public IPv4 (attached and idle Elastic IPs both cost; see [VPC pricing](https://aws.amazon.com/vpc/pricing/)), RDS compute, storage and backups, Route 53 and outbound data. The defaults (`t3a.small`, `db.t4g.micro`, 20 GiB storage) suit a very low-traffic app; check regional pricing first.

## Connecting Kamal

```sh
terraform output application_server_public_ip   # → CYCLEFAR_WEB_HOST
terraform output database_endpoint              # → CYCLEFAR_DB_HOST
terraform output -raw database_password         # → DB_PASSWORD secret
```

Kamal fixes `DB_PORT=5432` and `DB_USERNAME=cyclefar`, so keep the infrastructure defaults or change `config/deploy.yml` to match. Registry, image, hostname and TLS are configured in `config/deploy.yml`, not Terraform. See the [README](../README.md#deployment) for the remaining deploy variables and secrets.
