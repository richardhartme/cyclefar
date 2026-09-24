# CycleFar on AWS with CloudFormation

`cyclefar.yaml` is an alternative to the Terraform configuration in `infra/`.
Choose one tool to own an environment; this template creates a new environment,
not an import of Terraform-managed resources. No stack has been deployed.

## Architecture

- One VPC (`10.20.0.0/16`), one public application subnet and an Internet Gateway.
- Ubuntu 24.04 AMD64 on one `t3a.small` EC2 instance, encrypted 20 GiB gp3 root disk,
  IMDSv2, an SSH key pair, and an Elastic IP.
- An EC2 IAM profile for Systems Manager; no database-secret permissions on the host.
- Two private database subnets in separate availability zones, with only local routing.
- One private, encrypted PostgreSQL RDS instance (`db.t4g.micro`), 20 GiB gp3 storage,
  storage autoscaling up to 50 GiB and seven days of backups. It accepts PostgreSQL
  only from the application security group.
- A generated 32-character database password in Secrets Manager. Neither parameters
  nor outputs contain the password. Rotation is not configured automatically.
- Optional DNS: create a public Route 53 zone and A record, use an existing zone,
  or leave DNS disabled.

There are no NAT gateways, load balancers, containers orchestrators or deployment
pipelines. Stack creation provisions infrastructure, not a running Rails application.
Docker installation and Rails deployment remain separate Kamal tasks. The current
`config/deploy.yml` is still a development placeholder.

## Prerequisites and parameters

Install AWS CLI v2 and optionally `cfn-lint`. Authenticate with your normal AWS SSO
profile, for example `aws sso login --profile cyclefar`, and set `AWS_PROFILE=cyclefar`.
Use a region with at least two available AZs and support for the selected EC2/RDS sizes.
The CLI `--region` selects the deployment region; no AWS credentials belong in this directory.
Your deploying identity needs CloudFormation and permissions to create the resources
above, including IAM roles, Secrets Manager secrets, and SSM public-parameter reads.

Create/import an EC2 key pair in that region first. Copy `parameters.example.json`
to `parameters.local.json` and replace the key name and documentation-only SSH CIDR
with your own key name and trusted public IP (`/32`). The example cannot provide SSH
access unchanged. Do not set SSH to `0.0.0.0/0`.

Other template parameters set project/environment, instance sizes, initial database
name/user and optional engine version. The Ubuntu SSM parameter resolves to Canonical's
current image; inspect replacements on later updates as that image changes.

For DNS, set `DNSMode` to `Existing` with `HostedZoneId`, or `Create` to create a new zone
for `DomainName` (default `cyclefar.com`). Creating a zone does not register a domain or
change registrar delegation. Set its output nameservers at your registrar after creation.
Use an existing delegated zone if you already host other records there. An existing A
record with the same name must be reconciled before this stack can create its record.

## Validate, review, then deploy manually

From the repository root:

```sh
cfn-lint infra/cloudformation/cyclefar.yaml
aws cloudformation validate-template \
  --region eu-west-2 \
  --template-body file://infra/cloudformation/cyclefar.yaml
```

The AWS command is a remote syntax check, not a deployment or a guarantee that all
region-specific resource settings will be accepted. Create a reviewable change set:

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

After reviewing the proposed resources, execute explicitly:

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

For later changes, create a change set with type `UPDATE` and a new change-set name.
Review EC2/RDS replacements carefully: a snapshot is a recovery point, not an automatic
transfer of database contents to a replacement. An EC2 replacement also removes local
files on its root disk and requires application deployment again.

## Connecting Rails with Kamal

Use `ApplicationPublicIP` for the Kamal host and `ubuntu` as the SSH user. Configure an
accessible container registry, the existing AMD64 image build, Docker setup, TLS/proxy,
and the production hostname separately before running `bin/kamal setup`.

Supply the stack's `DatabaseEndpoint`, `DatabasePort` and `DatabaseUsername` as `DB_HOST`,
`DB_PORT` and `DB_USERNAME`. Retrieve the password privately using the Secrets Manager
console and `DatabaseSecretArn`, and supply it as the `DB_PASSWORD` Kamal secret.
`RAILS_MASTER_KEY` is a separate required secret. Never paste credentials into the template,
parameters, Git, or CloudFormation outputs. Changes to the secret alone do not update
RDS or already-running containers: coordinate any future password rotation with both.

The template's initial database is `cyclefarproduction`. Rails currently uses
`cycle_far_production`, `cycle_far_production_cache`, `cycle_far_production_queue` and
`cycle_far_production_cable`. Run `bin/rails db:prepare` through the production container
on the EC2 host with its database credentials to create these databases and load their
schemas (the Docker entrypoint also prepares the database on app startup). The RDS master
user has the privileges needed for this initial setup. The initial database can remain
unused; setting DB_HOST alone does not change Rails's database names.

## Costs and cleanup

EC2, EBS, public IPv4 (including an attached Elastic IP), RDS compute/storage/backups,
Secrets Manager, optional Route 53 hosted zones/queries, and outbound data transfer
incur costs. Snapshots and retained secrets continue to incur charges after deletion.

To remove the environment deliberately:

```sh
aws cloudformation delete-stack --region eu-west-2 --stack-name cyclefar-production
aws cloudformation wait stack-delete-complete --region eu-west-2 --stack-name cyclefar-production
```

RDS is snapshotted on deletion or replacement. Its secret is retained so the saved
credentials remain available for recovery; manage retained snapshots and secrets manually.
A newly created hosted zone cannot be deleted while it contains additional records added
outside the stack. Existing hosted zones are never managed or deleted by this template.

## References

- [CloudFormation RDS resource](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-rds-dbinstance.html)
- [Secrets Manager dynamic references](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/dynamic-references-secretsmanager.html)
