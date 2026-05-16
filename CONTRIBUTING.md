# Contributing

Thanks for helping improve this FFmpeg Lambda layer for Amazon Linux 2023.

## Before you start

- Search [existing issues](https://github.com/cookiemonsterdev/ffmpeg-aws-lambda-layer/issues) to avoid duplicates.
- For large changes (FFmpeg version bumps, new architectures, SAR metadata), open an issue first so we can align on scope.

## Development setup

Prerequisites match the [README](README.md):

- `bash`, `curl`, `tar`, `xz`
- AWS CLI and AWS SAM CLI (for `make publish` only)
- AWS credentials if you plan to deploy or publish

```bash
make build                    # stage ffmpeg/ffprobe into build/layer/bin
make build ARCH=arm64         # Graviton static build
make clean && make build      # force re-download from upstream
```

`make deploy` and `make publish` require `DEPLOYMENT_BUCKET` and real AWS resources. You do not need them for layer packaging changes.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Keep changes focused; unrelated refactors make review harder.
3. If you change `template.yaml` SAR metadata, bump `SemanticVersion` only when preparing a release (maintainers may handle this on merge).
4. Update `README.md` when behavior, paths, or Makefile variables change.
5. Open a PR and fill out the template checklist.

## Licensing

Bundled FFmpeg is GPL-3.0-or-later. Contributions to this repository are accepted under the same license as the project ([LICENSE](LICENSE)). Do not submit proprietary or incompatible-licensed binary blobs.

## Code review

Pull requests may require approval from [code owners](.github/CODEOWNERS) when that branch protection rule is enabled.

## Questions

Use [GitHub Discussions](https://github.com/cookiemonsterdev/ffmpeg-aws-lambda-layer/discussions) or open an issue labeled as a question if Discussions are not enabled.
