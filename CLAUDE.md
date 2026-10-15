# CLAUDE.md – wp-test-env

General Docker test environment for WordPress themes and plugins: fresh, isolated instances (one Compose project each, everything on tmpfs) for browser, WP-CLI and release tests and benchmarks, run in parallel from pool files. It lives next to the projects it tests (the parent directory is the workspace, mounted as `/workspace`; `WP_TEST_ENV_WORKSPACE` selects another one). The README is the user documentation; this file lists what matters when changing the environment.

<!-- Maintainers: keep this file under 200 lines. -->

## Rules

- **Stay general.** Nothing here refers to a specific theme, plugin or library: no project names in scripts, compose files or README. Projects describe their tests in their own pool files.
- **Nothing persists and nothing is shared between instances:** database, core and uploads on tmpfs; one Valkey per instance (the object cache drop-in's flush empties the whole database); only the WordPress container joins the shared network `wp-test-env`. Never put `db`, `valkey` or `mail` on that network: every instance has services of those names, and Docker DNS would pick any of them. Never address an instance by the service name `wordpress` there.
- **No host ports, no `.env`:** the workspace is the parent directory unless `WP_TEST_ENV_WORKSPACE` names another one (resolved and exported in `lib/common.sh`, so every command a run starts sees the same workspace); the administrator is fixed in `lib/common.sh`; test runners reach instances at `http://<instance>.test` on the network.
- **Projects are paths relative to the workspace** (nested allowed, never `.`/`..`; `check_project_path`, `check_project_slugs` in `lib/common.sh`), linked under their last path segment.
- **The workspace is read-only in instances;** only `bin/tools` writes to it, as the host user. Relative symlinks must resolve on the host and in every container.
- **Published images are tagged with the hash of their `docker/<image>/` directory** (`image_hash` in `lib/common.sh`); `.github/workflows/images.yml` publishes them on changes and daily. Everything an image needs must live in its directory, so the hash covers it. After changing `docker/`, test with `bin/build` (it builds the unpublished image locally).
- **The images are kept apart from those of the development environment on purpose** (`docker/wordpress`, `docker/tools`): the test environment must not depend on it. When one of them changes, consider the other.
- **Scripts are idempotent and fail loudly:** `set -euo pipefail`, clear `ERROR:` messages naming the instance, file, line or project at fault, no silent fallbacks. Shared code goes to `lib/common.sh`.
- **The interface for projects is a contract:** the variables `bin/e2e` passes (`WP_BASE_URLS`, `WP_USERNAME`, `WP_PASSWORD`, `E2E_TARGET`, `E2E_OUTPUT_DIR`, `PLAYWRIGHT_VERSION`), the script name `test:e2e`, the instance URL `http://<instance>.test`, the commands of `bin/` and the pool file format. Change them only together with the projects that use them, and keep the README in sync.
- Verify the behavior of images, Docker Compose, Playwright and WP-CLI in their documentation or source before relying on it; say clearly when something is not verified.
- Everything in this repository is English; other repositories are linked by GitHub URL.

## Commands

Run from this directory.

```sh
bin/build                                                   # pulls the published images; builds after changing docker/
bin/up smoke --theme <dir> --activate <dir>                 # a dev instance
bin/wp smoke option get home                                # WP-CLI
bin/down --all
bin/run <pool file>...                                      # whole test setups
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable -x bin/* lib/common.sh docker/wordpress/docker-entrypoint-test.sh
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12   # after changing .github/workflows/
```

## Definition of done for changes

- `shellcheck` reports nothing (command above).
- `bin/up` starts a dev instance and a release instance; in the release instance the write probe fails as expected; `bin/up` again replaces an instance of the same name.
- A run of `bin/run` with pool files of real projects passes twice in a row; afterwards `docker ps -a` shows no container and `docker network ls` no network of wp-test-env.
- README, the usage comments of the scripts and `compose.yaml` describe the same commands, options and variables.
