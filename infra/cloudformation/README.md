# CycleFar on AWS with CloudFormation

`cyclefar.yaml` is an alternative to the [Terraform configuration](../README.md). Use one tool per environment. The template creates a new environment; it can't import Terraform-managed resources, and the repository doesn't record which tool owns the live `cyclefar.com` resources, so check before creating a stack.

## Architecture

- One VPC (`10.20.0.0/16`) with a public application subnet and an Internet Gateway.
- One `t3a.small` Ubuntu 24.04 AMD64 instance: encrypted 20 GiB gp3 disk, IMDSv2, SSH key pair, Elastic IP, and an IAM profile for Systems Manager (no database-secret access).
- Two private database subnets in separate AZs, with local routing only.
- One private, encrypted PostgreSQL RDS instance (`db.t4g.micro`, 20 GiB gp3 autoscaling to 50 GiB, seven days of backups), reachable only from the application security group.
- A generated 32-character database password in Secrets Manager, never in parameters or outputs. Rotation isn't configured.
- Optional DNS: create a public Route 53 zone and A record, use an existing zone, or none.

No NAT gateways, load balancers, orchestrators or pipelines. The stack provisions infrastructure only; Docker and the app are deployed separately with Kamal.

## Prerequisites and parameters

- AWS CLI v2 (and optionally `cfn-lint`), authenticated through your SSO profile (`aws sso login --profile cyclefar`, `AWS_PROFILE=cyclefar`). No credentials belong in this directory.
- A region with at least two AZs and the chosen instance sizes.
- Permission to use CloudFormation and create the resources above, including IAM roles, Secrets Manager secrets and SSM public-parameter reads.
- An EC2 key pair in that region.

Copy `parameters.example.json` to `parameters.local.json` and set your key name and trusted SSH CIDR (`/32`); the example's documentation CIDR grants no access, and never use `0.0.0.0/0`. Other parameters cover project/environment, instance sizes, initial database name and user, and engine version. The Ubuntu image comes from Canonical's SSM parameter, so check for instance replacement on later updates.

For DNS, set `DNSMode` to `Existing` with `HostedZoneId`, or to `Create` for a new zone for `DomainName` (default `cyclefar.com`). Creating a zone doesn't register the domain or change delegation: set the output nameservers at your registrar. An existing A record with the same name must be removed first.

## Validate, review, then deploy manually

From the repository root:

```sh
cfn-lint infra/cloudformation/cyclefar.yaml
aws cloudformation validate-template \
  --region eu-west-2 \
  --template-body file://infra/cloudformation/cyclefar.yaml
```

`validate-template` is a syntax check only. Create and review a change set:

```sh
aws cloudformation create-change-set \
  --region eu-west-2 \
  --stack-name cyclefar-production \
  --change-set-name initial-infrastructure \
  --change-set-type CREATE \
  --template-body file://infra/cloudformation/cyclefar.yaml \
  --parameters file://infra/cloudformation/parameters.local.json \
  --capabilities CAPABILITY_IAM \
  --tags Key=Project,Value=cyclefar Key=Environment,Value=production

aws cloudformation wait change-set-create-complete \
  --region eu-west-2 --stack-name cyclefar-production \
  --change-set-name initial-infrastructure

aws cloudformation describe-change-set \
  --region eu-west-2 --stack-name cyclefar-production \
  --change-set-name initial-infrastructure
```

Then execute it:

```sh
aws cloudformation execute-change-set \
  --region eu-west-2 --stack-name cyclefar-production \
  --change-set-name initial-infrastructure
aws cloudformation wait stack-create-complete \
  --region eu-west-2 --stack-name cyclefar-production
aws cloudformation describe-stacks \
  --region eu-west-2 --stack-name cyclefar-production \
  --query 'Stacks[0].Outputs'
```

For later changes, use an `UPDATE` change set with a new name. Watch for EC2 or RDS replacement: a snapshot is a recovery point, not a data migration, and a replaced EC2 instance loses its local files and needs redeploying.

## Connecting Kamal

| Stack output | Use |
|---|---|
| `ApplicationPublicIP` | `CYCLEFAR_WEB_HOST` (SSH user `ubuntu`) |
| `DatabaseEndpoint` | `CYCLEFAR_DB_HOST` |
| `DatabaseSecretArn` | Retrieve the password privately and supply it as the `DB_PASSWORD` secret |

Kamal fixes `DB_PORT=5432` and `DB_USERNAME=cyclefar`; keep `DatabasePort` and `DatabaseUsername` at their defaults or change `config/deploy.yml` to match. Never put credentials in the template, parameters, Git or outputs. Changing the secret alone doesn't update RDS or running containers, so coordinate any rotation with both. See the [README](../../README.md#deployment) for the remaining deploy variables and secrets.

The template's initial database, `cyclefarproduction`, can stay unused. Rails uses `cycle_far_production` plus `_cache`, `_queue` and `_cable` databases; run `bin/rails db:prepare` in the production container (the Docker entrypoint also does this) to create them.

## Costs and cleanup

EC2, EBS, public IPv4 (including the attached Elastic IP), RDS compute, storage and backups, Secrets Manager, Route 53 and outbound data all cost money. Snapshots and retained secrets keep costing after deletion.

```sh
aws cloudformation delete-stack --region eu-west-2 --stack-name cyclefar-production
aws cloudformation wait stack-delete-complete --region eu-west-2 --stack-name cyclefar-production
```

RDS is snapshotted on deletion or replacement, and its secret is retained for recovery; clean both up manually. A created hosted zone can't be deleted while it holds records added outside the stack. Existing zones are never managed or deleted.

## References

- [CloudFormation RDS resource](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-rds-dbinstance.html)
- [Secrets Manager dynamic references](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/dynamic-references-secretsmanager.html)
