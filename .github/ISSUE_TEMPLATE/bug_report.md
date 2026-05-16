---
name: Bug report
about: Something is broken in the layer build, packaging, or usage on Lambda
title: "[Bug] "
labels: bug
assignees: ""
---

## Describe the bug

A clear description of what went wrong.

## Steps to reproduce

1. Command or SAM/CloudFormation snippet used
2. Lambda runtime and architecture (`nodejs20.x`, `provided.al2023`, `x86_64` / `arm64`, etc.)
3. Whether you used the published SAR app or `make build` / `make deploy` locally

## Expected behavior

What you expected to happen.

## Actual behavior

Include error messages, CloudFormation events, or Lambda log excerpts (redact account IDs if needed).

## Environment

- Layer version or git commit:
- `ARCH` used for build (`amd64` / `arm64`):
- AWS region:
- Host OS used to run `make build` (macOS / Linux):

## Additional context

Screenshots, `template.yaml` snippets, or links to related issues are welcome.
