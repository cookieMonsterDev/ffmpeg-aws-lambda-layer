# ---------------------------------------------------------------------------
# ffmpeg-lambda-layer-for-amazon-linux-2023
#
# This Makefile is intentionally a small superset of the reference Makefile
# from `serverlesspub/ffmpeg-aws-lambda-layer` (the public app currently
# listed in SAR). It keeps the same idioms:
#
#   - File-based targets (`build/layer/bin/ffmpeg`, `build/output.yaml`)
#     instead of always-rerunning `.PHONY` recipes, so make can skip work
#     that is already up-to-date.
#   - `aws cloudformation package` to upload the layer zip to S3 and
#     rewrite the template, followed by `aws cloudformation deploy` for
#     a normal CFN stack.
#   - A small set of well-known variables, each settable from the command
#     line with `make TARGET VAR=value`.
#
# The only additions over the reference are:
#   - A `publish` target that calls `sam publish` (needed for SAR; vanilla
#     `aws cloudformation` cannot push to the Serverless App Repository).
#   - `ARCH` to pick the static-build flavour (amd64 vs arm64).
#   - `REGION` so multi-region pipelines do not have to rely on the
#     ambient AWS_REGION env var.
#
# ---------------------------------------------------------------------------
# Variables (override on the command line, e.g. `make deploy DEPLOYMENT_BUCKET=my-bucket`)
# ---------------------------------------------------------------------------
#
#   DEPLOYMENT_BUCKET  S3 bucket that `aws cloudformation package` and
#                      `sam publish` use to store the packaged layer zip.
#                      REQUIRED for `package`, `deploy`, `publish`.
#
#   STACK_NAME         CloudFormation stack name used by `make deploy`.
#                      Default: ffmpeg-lambda-layer-for-amazon-linux-2023
#
#   REGION             AWS region for all CLI calls.
#                      Default: us-east-1 (the canonical SAR region).
#
#   ARCH               Which static build to download.
#                      amd64 (default) maps to x86_64 Lambda runtimes.
#                      arm64 maps to Graviton (aarch64) Lambda runtimes.
#                      Remember to also flip CompatibleArchitectures in
#                      template.yaml when building an arm64 layer.
#
# ---------------------------------------------------------------------------

STACK_NAME ?= ffmpeg-lambda-layer-for-amazon-linux-2023
REGION     ?= us-east-1
ARCH       ?= amd64

.PHONY: clean deploy publish help

help:
	@echo "Targets:"
	@echo "  make build              - stage ffmpeg/ffprobe into build/layer/bin"
	@echo "  make deploy             - deploy as a CloudFormation stack (testing)"
	@echo "                            requires DEPLOYMENT_BUCKET=<your-bucket>"
	@echo "  make publish            - publish to the Serverless App Repository"
	@echo "                            requires DEPLOYMENT_BUCKET=<your-bucket>"
	@echo "  make clean              - remove ./build"

clean:
	rm -rf build/

build: build/layer/bin/ffmpeg

# File target: only re-runs build.sh when the binary is missing.
# `make clean` deletes it, so a fresh build forces a re-download.
build/layer/bin/ffmpeg:
	ARCH=$(ARCH) ./build.sh

# File target: re-packages when either the template or the binary changes.
# `aws cloudformation package` walks template.yaml, finds the
# `ContentUri: build/layer` reference, zips that directory, uploads the zip
# to s3://$(DEPLOYMENT_BUCKET)/..., and rewrites the URI to a CodeUri
# pointing at the uploaded zip. The result is build/output.yaml.
build/output.yaml: template.yaml build/layer/bin/ffmpeg
	@if [ -z "$(DEPLOYMENT_BUCKET)" ]; then \
	  echo "ERROR: DEPLOYMENT_BUCKET is required (e.g. make deploy DEPLOYMENT_BUCKET=my-bucket)"; \
	  exit 1; \
	fi
	aws cloudformation package \
	  --template-file $< \
	  --s3-bucket $(DEPLOYMENT_BUCKET) \
	  --output-template-file $@ \
	  --region $(REGION)

deploy: build/output.yaml
	aws cloudformation deploy \
	  --template-file $< \
	  --stack-name $(STACK_NAME) \
	  --region $(REGION)
	aws cloudformation describe-stacks \
	  --stack-name $(STACK_NAME) \
	  --region $(REGION) \
	  --query 'Stacks[].Outputs' \
	  --output table

# `sam publish` reads the packaged template (where the SAR Metadata block
# lives) and creates or updates the application in the Serverless App
# Repository. It requires the same S3 bucket that `package` uploaded to,
# and that bucket must allow `serverlessrepo.amazonaws.com` to GetObject
# (see README "Step 1.3" for the policy).
publish: build/output.yaml
	sam publish \
	  --template $< \
	  --region $(REGION)
