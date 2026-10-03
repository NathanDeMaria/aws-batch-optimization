# infra

The shared AWS Batch stack: queue, compute environment, network, buckets, ECR
repositories, and the IAM that ties them together.

## CI

`terraform` runs in GitHub Actions ([`.github/workflows/terraform.yml`][wf]),
following the same pattern as [invisible-string][is]:

| Job | When | Credentials |
| --- | --- | --- |
| `lint` | every push and PR touching `infra/**` | none |
| `plan` | every branch and PR except main | `AWS_PLAN_ROLE_ARN` |
| `apply` | push to main | `AWS_APPLY_ROLE_ARN` |

[wf]: ../.github/workflows/terraform.yml
[is]: https://github.com/NathanDeMaria/invisible-string/tree/main/infra

Plans comment on the PR and update in place, so a chatty branch doesn't
accumulate one plan comment per push.

### Why two roles

`terraform plan` executes provider code and runs on every branch and PR,
including from a fork's PR if that's ever enabled. It must not be able to reach
credentials that can change anything. So:

- **plan role** — `ReadOnlyAccess`, plus write on this stack's state object and
  its lock file. Trusts `ref:refs/heads/*` *and* `pull_request`, because a PR's
  OIDC subject carries no ref at all — a policy trusting only refs fails on
  every PR.
- **apply role** — `PowerUserAccess` (everything but IAM) plus IAM scoped to
  the names this stack owns. Trusts `refs/heads/main` literally, so a branch
  named `main-hotfix` can't match.

`PowerUserAccess` denies IAM outright, and this stack is mostly IAM, so the
apply role carries a hand-written policy for it. invisible-string scopes that
to a single `${prefix}-*`; here the pre-existing roles are named `job-role`,
`ecs_instance_role`, `spot-fleet-role` and `aws_batch_service_role`, so those
four are listed individually and everything new goes under `batch-*`. Keep new
IAM under that prefix and the list stops growing.

The sharpest grant is `iam:CreateAccessKey`, scoped to the users on the
`/system/` path this stack owns. No ECR repository has a push user any more:
endgame, cassandra and gold-rush each push from CI by OIDC, with an image role
their own `jobs/` stack owns, so `repos/` creates repositories and nothing
else.

### Setup

The roles are created by this stack, so the first apply is from a laptop.

```bash
make apply                 # creates batch-ci-plan and batch-ci-apply
gh variable set AWS_PLAN_ROLE_ARN  --body "$(terraform output -raw ci_plan_role_arn)"
gh variable set AWS_APPLY_ROLE_ARN --body "$(terraform output -raw ci_apply_role_arn)"
```

Repository **variables**, not secrets — a role ARN isn't secret, and the
workflow compares them against `''` to stay dormant until they're set. Before
that, `lint` is the only job that runs; `plan` and `apply` skip rather than
fail red.

`create_oidc_provider` defaults to **false** here. IAM permits one OIDC
provider per URL per account and invisible-string creates one in this same
account, so this stack expects to find it. If this account has none yet, set it
true here and false there.

## Failure alerts

`alerts.tf` emails when any job on the queue fails: one EventBridge rule on the
queue, one SNS topic (`batch-failures`), one email subscription. The app repos
declare no Batch failure rule of their own, so a new app is covered without
doing anything, and nobody gets the same failure twice. Array children are
filtered out, so a failed array sends one email, not one per child.

The topic ARN is in `/batch/shared-outputs` as `failure_topic_arn`, for alerts
that aren't a job failing: endgame points its Step Functions chain failures at
it.

The address is the `NOTIFICATION_EMAIL` secret in CI (`notification_email`
locally). A new subscription only delivers after the confirmation link AWS
emails to it has been clicked.

## Local use

```bash
make plan
make apply
make outputs      # applies, then writes ~/.aws-batch/config.json
make lint         # what CI runs; no credentials needed
```

`make outputs` is what the app repos read for bucket names, the queue name and
ECR URLs on a laptop. It contains ECR push credentials, so it stays out of the
repo.

Their terraform and CI read the same values from the SSM parameter
`/batch/shared-outputs` instead (`ssm.tf`): only the non-sensitive outputs, as
JSON keyed by output name, so a role can be granted that one parameter rather
than the whole state file.

## Debugging

`batch-debug` (`debug.tf`) is for looking into jobs by hand, across every app
on the queue: describe and list jobs, read `/aws/batch/job` logs, schedules,
image tags and both buckets, and submit, cancel or terminate jobs on the
shared queue. It changes no infrastructure and passes no role, so a submitted
job runs with the roles its definition already names.

It's assumed from the `batch-debug` user on `/system/`, which can do nothing
but that. The user's access key is made by hand so it never lands in state:

```bash
aws iam create-access-key --user-name batch-debug
```

Then, wherever the key lives (a laptop, or a Claude Code environment's
settings as `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`), a profile that
assumes the role from it:

```ini
# ~/.aws/config
[profile batch-debug]
role_arn          = arn:aws:iam::<account>:role/batch-debug
credential_source = Environment
```

To let another identity debug, add it to the role's trust rather than handing
out a second key.

## Notes

- The provider deliberately does **not** set `profile = "default"`. OIDC hands
  credentials to Actions as environment variables, and naming a profile makes
  the provider look for `~/.aws/credentials` and fail. With no profile named
  the SDK still reads the `default` profile locally, so nothing changes there.
- The S3 backend uses `use_lockfile` (S3-native locking, no DynamoDB table).
  That matters now that CI applies: two overlapping runs would otherwise write
  the same state with nothing stopping them.
- The data bucket is **versioned, with noncurrent versions expiring after 30
  days**. Its objects are rewritten in place — the season files are replaced
  wholesale by every daily job run — so without versions a bad pull overwrites
  good data with no way back. The window is the entire cost dial: the objects
  churn daily, so N days of retention is roughly N stale copies of each, and
  the steady-state bill is (bytes rewritten per day) x N. The temp bucket is
  left unversioned, since everything in it expires after seven days anyway.
