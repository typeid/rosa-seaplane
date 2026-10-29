# Terraform Configurations

## CI/CD Pipelines

For the current per-cluster pipeline architecture and lifecycle, see [CodePipeline Cluster Lifecycle](../../docs/design/codepipeline-cluster-lifecycle.md).

### `region-bootstrap/` and `region-dns/`

Applied by `scripts/bootstrap-region.sh` from the central account, once per RC. `region-bootstrap/` runs with RC account credentials and creates the CodeStar connection, the `codepipeline-shared` module (artifact bucket, CodePipeline role, RC and MC CodeBuild roles), and failure notifications. `region-dns/` creates the regional hosted zone in the RC account and its NS delegation in the central environment zone, using the `delegated-zone` module. The connection must be authorized manually in the RC account's AWS Console. `scripts/provision-cluster-resources.sh` dynamically creates one CodePipeline and one CodeBuild project per RC or MC in the RC account.

### `codebuild-regional-cluster/` and `codebuild-management-cluster/`

Contain the combined per-cluster buildspecs. Cluster pipeline and CodeBuild definitions are reconciled through AWS APIs; cluster infrastructure remains Terraform-managed.

## Cluster Infrastructure

### `regional-cluster/`

Provisions the full regional cluster stack in the RC account (the regional hosted zone itself comes from `region-bootstrap/`): EKS, VPC, API Gateway, kube-applier DynamoDB tables, RDS (seaplane-db), ECS bootstrap, optional CloudTrail audit logging (disabled by default; enable with `enable_cloudtrail` for compliance environments), and optional bastion.

### `management-cluster/`

Provisions a management cluster: private EKS (1–2 nodes), ECS bootstrap, kube-applier IAM, and optional bastion. Hosts customer control planes.
