# ffmpeg-lambda-layer-for-amazon-linux-2023

An AWS Lambda **Layer** that bundles a **static FFmpeg & ffprobe**
release, ready to use on the **Amazon Linux 2023** Lambda runtimes
(`nodejs20.x`, `nodejs22.x`, `python3.12`, `python3.13`,
`provided.al2023`, and friends).

The binaries come from [johnvansickle.com](https://johnvansickle.com/ffmpeg/)'s
"release" tarball — the de-facto static FFmpeg distribution. The script
fetches the unversioned `ffmpeg-release-{arch}-static.tar.xz` URL, so it
automatically rolls forward as upstream publishes new versions
(currently **FFmpeg 7.0.2**, will move to 7.1.x → 8.x as the mirror
catches up). They are built against glibc 2.17, so they run unmodified
on AL2023's glibc 2.34.

Once the layer is attached to a function, the binaries are available at:

```
/opt/bin/ffmpeg
/opt/bin/ffprobe
```

`/opt/bin` is already on `$PATH` in every Lambda runtime, so your handler
can just call `ffmpeg ...` / `ffprobe ...` directly.

### Why not FFmpeg 8.1?

The only public 8.1 static distribution today is
[BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds). Its
`linux64-gpl-8.1` binary is ~203 MB per executable; `ffmpeg + ffprobe`
totals ~387 MB unzipped — far over Lambda's **250 MB function + layers
unzipped** quota. The LGPL variant is no smaller (~352 MB combined). For
a usable 8.1 layer we would need to either:

1. Build FFmpeg 8.1 from source in an AL2023 container with
   `--disable-everything` + a minimal feature set (~50–80 MB),
2. or UPX-compress BtbN's binary (cuts size ~50% at the cost of cold
   start latency).

Both are bigger projects than the current scope. Switching to BtbN once
they ship a slimmer build, or doing our own source build, is on the
roadmap. Until then this layer ships the johnvansickle 7.x release line.

---

## Repository layout

```
.
├── build.sh                       # downloads + stages ffmpeg into build/layer/bin
├── template.yaml                  # SAM template + AWS::ServerlessRepo metadata
├── Makefile                       # build / deploy / publish, modeled on the
│                                  # serverlesspub reference example
├── LICENSE                        # GPL-3.0 (matches the bundled FFmpeg)
├── NOTICE                         # attribution & licensing notes
└── README.md
```

`./build/layer/` is generated at build time and contains:

```
build/layer/
└── bin/
    ├── ffmpeg
    └── ffprobe
```

---

## Quick start — use the published layer

Once the app is published in the Serverless Application Repository (SAR),
anyone can deploy it into their account with a single `sam deploy` or via
the AWS console. The stack output `LayerVersionArn` is what you attach to
your Lambda functions.

Example consumer SAM template:

```yaml
Transform: AWS::Serverless-2016-10-31

Resources:
  Ffmpeg:
    Type: AWS::Serverless::Application
    Properties:
      Location:
        ApplicationId: arn:aws:serverlessrepo:us-east-1:<YOUR_ACCOUNT_ID>:applications/ffmpeg-lambda-layer-for-amazon-linux-2023
        SemanticVersion: 1.0.0

  Transcoder:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: nodejs20.x
      Handler: index.handler
      CodeUri: src/
      MemorySize: 1024
      Timeout: 60
      Layers:
        - !GetAtt Ffmpeg.Outputs.LayerVersionArn
```

Minimal Node.js handler:

```js
import { spawnSync } from "node:child_process";

export const handler = async () => {
  const out = spawnSync("ffmpeg", ["-version"], { encoding: "utf8" });
  return { stdout: out.stdout, stderr: out.stderr, code: out.status };
};
```

---

## Building it yourself

Prerequisites:

- macOS or Linux with `bash`, `curl`, `tar`, `xz`
- [AWS CLI](https://aws.amazon.com/cli/) (used for `aws cloudformation package` / `deploy`)
- [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html) (used only for `make publish`)
- AWS credentials configured (`aws configure` or SSO)

### Makefile variables

Override any of these on the command line, e.g.
`make deploy DEPLOYMENT_BUCKET=my-bucket ARCH=arm64`.

| Variable            | Required for                              | Default                                     | What it does                                                                                                                                                                      |
| ------------------- | ----------------------------------------- | ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DEPLOYMENT_BUCKET` | `deploy`, `publish`                       | _(none, must be set)_                       | S3 bucket used by `aws cloudformation package` and `sam publish` to upload the layer zip. SAR also reads from this bucket — see "S3 bucket policy" below.                         |
| `STACK_NAME`        | `deploy`                                  | `ffmpeg-lambda-layer-for-amazon-linux-2023` | CloudFormation stack name created/updated by `make deploy`.                                                                                                                       |
| `REGION`            | all targets                               | `us-east-1`                                 | AWS region for every CLI call. `us-east-1` is the canonical region for SAR.                                                                                                       |
| `ARCH`              | `build` (and anything that depends on it) | `amd64`                                     | Picks which static tarball to download. `amd64` → x86_64 Lambda; `arm64` → Graviton. Remember to flip `CompatibleArchitectures` in `template.yaml` if you publish an arm64 layer. |

### File-target idiom

The Makefile uses make's natural dependency tracking, just like the
reference `serverlesspub/ffmpeg-aws-lambda-layer`:

- `build/layer/bin/ffmpeg` — recipe runs `./build.sh`; **skipped if the
  file already exists**. Use `make clean` to force a re-download.
- `build/output.yaml` — recipe runs `aws cloudformation package`;
  **re-runs only if `template.yaml` or the staged binary changed**.
- `deploy` and `publish` depend on `build/output.yaml`, so they
  transparently trigger packaging when needed.

### Build flow

```bash
make build                              # 1. stage ffmpeg/ffprobe (downloads ~25 MB tarball)
make deploy DEPLOYMENT_BUCKET=my-bucket # 2. (optional) test the layer in your own account
```

`make build` produces `./build/layer/bin/ffmpeg` and
`./build/layer/bin/ffprobe`, verified against the upstream MD5 checksum.

To clean up a test deployment:

```bash
aws cloudformation delete-stack --stack-name ffmpeg-lambda-layer-for-amazon-linux-2023
```

> Note: the layer has `RetentionPolicy: Retain`, so deleting the stack
> does **not** delete the layer version. Delete it manually if needed:
> `aws lambda delete-layer-version --layer-name ffmpeg --version-number N`.

---

## Publishing to the AWS Serverless Application Repository (SAR)

End-state goal: your application appears at
[serverlessrepo.aws.amazon.com/applications](https://serverlessrepo.aws.amazon.com/applications)
under the name **`ffmpeg-lambda-layer-for-amazon-linux-2023`**.

### Step 1 — One-time setup

**1.1. Pick a region.** SAR is a regional service; `us-east-1` is the
most common publishing region. Set it once for the session:

```bash
export AWS_REGION=us-east-1
```

**1.2. Create an S3 bucket** that will hold packaged layer zips:

```bash
aws s3 mb s3://my-sar-artifacts-<your-suffix> --region us-east-1
```

**1.3. Allow SAR to read from that bucket.** Save the policy below as
`bucket-policy.json` (replace `REPLACE_*` first), then apply it:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowServerlessRepoReadAccess",
      "Effect": "Allow",
      "Principal": { "Service": "serverlessrepo.amazonaws.com" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::REPLACE_WITH_YOUR_BUCKET_NAME/*",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "REPLACE_WITH_YOUR_AWS_ACCOUNT_ID"
        }
      }
    }
  ]
}
```

```bash
aws s3api put-bucket-policy \
  --bucket my-sar-artifacts-<your-suffix> \
  --policy file://bucket-policy.json
```

Without this policy the publish step will fail with `Access Denied`.

**1.4. Fill in your metadata** in `template.yaml` under
`Metadata.AWS::ServerlessRepo::Application`:

- `Author` — your name or org
- `HomePageUrl`, `SourceCodeUrl` — currently
  `https://github.com/cookiemonsterdev/ffmpeg-aws-lambda-layer`
- `SemanticVersion` — bump for every release (`1.0.0`, `1.0.1`, …)

### Step 2 — Build, package, publish

```bash
make build
make publish DEPLOYMENT_BUCKET=my-sar-artifacts-<your-suffix>
```

`make publish` internally runs `aws cloudformation package` to upload
the layer zip and rewrite the template to `build/output.yaml`, then
calls `sam publish --template build/output.yaml --region us-east-1`.

On success you'll see output similar to:

```
Publish Succeeded
Created new application with the following metadata:
{
  "Name":"ffmpeg-lambda-layer-for-amazon-linux-2023",
  "Description":"Latest static FFmpeg & ffprobe ...",
  "Author":"Your Name",
  ...
  "SemanticVersion":"1.0.0",
  "SourceCodeUrl":"https://github.com/cookiemonsterdev/ffmpeg-aws-lambda-layer"
}

Click the link below to view your application in AWS console:
https://console.aws.amazon.com/serverlessrepo/home?region=us-east-1#/published-applications/arn:aws:serverlessrepo:us-east-1:<ACCOUNT_ID>:applications~ffmpeg-lambda-layer-for-amazon-linux-2023
```

At this point the app is **private** — only your account can see it.

### Step 3 — Share or publish publicly

You can share the app with specific accounts, or make it public so it
shows up on the [public SAR listing](https://serverlessrepo.aws.amazon.com/applications).

```bash
APP_ARN="arn:aws:serverlessrepo:us-east-1:<ACCOUNT_ID>:applications/ffmpeg-lambda-layer-for-amazon-linux-2023"

# Public (anyone can deploy)
aws serverlessrepo put-application-policy \
  --application-id "$APP_ARN" \
  --statements Principals=*,Actions=Deploy \
  --region us-east-1

# Shared with specific accounts
aws serverlessrepo put-application-policy \
  --application-id "$APP_ARN" \
  --statements Principals=111122223333,444455556666,Actions=Deploy \
  --region us-east-1
```

> AWS reviews newly-public applications before they appear on the public
> SAR website. The app is immediately deployable via
> `arn:aws:serverlessrepo:...` once the policy is applied, but the
> browsable public listing can take a few hours to a day to show up.

### Step 4 — Releasing a new version

1. Bump `Metadata.AWS::ServerlessRepo::Application.SemanticVersion` in
   `template.yaml` (`1.0.0` → `1.0.1`, etc.).
2. Re-run the build + publish chain:

   ```bash
   make clean
   make publish DEPLOYMENT_BUCKET=my-sar-artifacts-<your-suffix>
   ```

`sam publish` will detect the existing application and add a new version
instead of creating a new one.

---

## Troubleshooting

- **`Access Denied` on `sam publish`** — the S3 bucket is missing the
  `serverlessrepo.amazonaws.com` `s3:GetObject` policy from Step 1.3.
- **`InvalidParameterValueException: Cannot find a license`** — make sure
  `LicenseUrl: LICENSE` points to a real file in the repo root; the
  current template already does.
- **Layer too large** — Lambda layers are limited to 250 MB unzipped
  (combined with function code and other layers) / ~70 MB zipped. The
  full GPL FFmpeg 7.x static build is ~152 MB unzipped, ~50 MB zipped —
  comfortably within limits. If you only need `ffmpeg` you can edit
  `build.sh` to skip copying `ffprobe`.
- **ARM64 functions** — re-run `make build ARCH=arm64`, change
  `CompatibleArchitectures` in `template.yaml` to `arm64`, bump the
  semver, and publish as a separate version (or a separate app, e.g.
  `ffmpeg-lambda-layer-for-amazon-linux-2023-arm64`).
- **Verify the binary on Lambda**:

  ```bash
  aws lambda invoke --function-name your-fn --payload '{}' /tmp/out.json
  cat /tmp/out.json   # should show ffmpeg version banner
  ```

---

## Licensing

The bundled FFmpeg build includes GPL components (x264, x265, …), so the
layer as a whole is distributed under **GPL-3.0-or-later**. See
[`LICENSE`](LICENSE) and [`NOTICE`](NOTICE) for the full terms and
attribution. If you need an LGPL-only build, see the note in `NOTICE`.
