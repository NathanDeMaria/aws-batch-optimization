---
name: wait-for-image
description: Wait until a repo's `latest` image in ECR is CI's build of a commit, before submitting AWS Batch jobs that run it. Use after merging a change to gold-rush, cassandra or any repo whose job definitions run `<repo>:latest` from the shared stack, whenever a job is about to be submitted or re-run with that change, or when asked whether an image has landed.
argument-hint: "[--profile NAME] [--repo OWNER/NAME] [SHA]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/wait-for-image.sh *)
---

# Waiting for a commit's image

The job definitions on the shared queue run `<repo>:latest`, and
`submit-job` can't override the image. So a job submitted between a merge
and CI's push runs the old image -- and succeeds, which is what makes it
easy to miss. Don't submit until this says the image is there.

Run it from a checkout of the repo whose image you need, **in the
background** (a slow build is a few minutes, and foreground `sleep` is
blocked):

```bash
${CLAUDE_SKILL_DIR}/wait-for-image.sh [--profile NAME] [SHA]
```

- No SHA means `origin/main`, fetched first. A SHA not in the checkout has
  to be the full 40 characters.
- `--profile` goes to every `aws` call. Pass it whenever a profile is in
  play: with access keys also in the environment, `AWS_PROFILE` alone is
  ignored and the calls go out as the wrong principal.
- `--repo OWNER/NAME` when running from somewhere else; `--ecr-repo` and
  `--workflow` if a repo doesn't follow the convention (ECR repo named
  after the GitHub repo, pushed by `.github/workflows/image.yml` as the
  7-character sha).

## What its exit code means

| exit | meaning | do |
|---|---|---|
| 0 | `latest` is the commit's build, or a later one that superseded it | submit |
| 1 | the image workflow failed, went green without pushing, or 20 minutes passed | stop; report the line it printed and the run URL |
| 2 | GitHub has no image workflow run for the commit | stop; it isn't on main, or the push didn't trigger CI |

Never submit on anything but 0, and don't work around a 1 by pushing an
image by hand -- report it. A green run that pushed nothing usually means
the repo's `AWS_IMAGE_ROLE_ARN` secret isn't set.
