# Contributing

Thanks for helping. This repository packages
[RuView](https://github.com/Justinwold88/RuView) as a Home Assistant app.
Sensing changes belong in RuView; changes here are about packaging, options,
docs and CI.

## Workflow

1. Open an issue first for anything larger than a small fix.
2. Branch from `main` and open a pull request. Titles follow
   [Conventional Commits](https://www.conventionalcommits.org/), for example
   `feat: add an option for the MQTT topic prefix`.
3. CI must pass: the app lint, ShellCheck, the start-script tests, and an image
   build with smoke tests on both architectures.

## Local checks

```bash
tests/run_options_test.sh          # needs bash and jq
shellcheck -s sh ruview/rootfs/usr/local/bin/ruview-run
shellcheck tests/run_options_test.sh
```

To build the image locally, check RuView out at the pinned commit first:

```bash
scripts/fetch-ruview.sh            # clones into ruview-src/ at ruview/RUVIEW_COMMIT
docker build -f ruview/Dockerfile -t ruview-addon:dev .
```

## Releasing a new version

1. Change `version` in `ruview/config.yaml` and add a section for it to
   `ruview/CHANGELOG.md`. CI checks that they match.
2. To ship a newer RuView, change `ruview/RUVIEW_COMMIT` to a commit on
   RuView's `main`.
3. Merge. CI publishes `ghcr.io/justinwold88/ruview-addon:<version>` for both
   architectures. It never overwrites a version that already exists.
