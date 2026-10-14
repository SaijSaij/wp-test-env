# wp-test-env

Docker test environment for WordPress themes and plugins: fresh, isolated WordPress instances on demand, for browser tests, WP-CLI tests, release tests and benchmarks, many of them in parallel. Nothing persists: database, WordPress core and uploads live on tmpfs, and every instance is gone after its run. On the host only Docker and Bash are needed.

It is the counterpart of a development environment such as [wp-dev-env](https://github.com/saijsaij/wp-dev-env): tests never touch the development site and its data.

## Layout

Check this repository out next to the projects it tests; the parent directory is the workspace, mounted as `/workspace`:

```
workspace/
├── wp-test-env/     this repository
├── my-theme/
└── my-plugin/
```

## Instances

Every instance is a Compose project of its own (`wp-test-env-<instance>`) with WordPress (latest stable version, PHP 8.5, Apache, WP-CLI), MariaDB, Mailpit and, on request, Valkey as persistent object cache. Only the WordPress container joins the shared Docker network `wp-test-env`, as `http://<instance>.test`; test runners in that network (Playwright, see below) reach it there. Instances publish no host ports, so they run next to any development environment.

An instance runs in one of two modes:

- **Dev mode** mounts the workspace read-only and links the given projects into `wp-content/themes` and `wp-content/plugins`, so the instance runs the checkouts.
- **Release mode** has no workspace: it installs release ZIPs with WP-CLI, activates them (a child theme instead of its parent) and makes their directories read-only, like a deployment without write access; a write probe as the web server user must fail.

Every instance has the administrator `admin` with the password `password`, `WP_DEBUG` on (log to the container log), pretty permalinks and no automatic updates.

## Commands

Run from this directory.

```sh
bin/build [--pull]                       # build the images (--pull: update WordPress and the service images)
bin/prepare [--link vendor/package=dir]... <project>...   # composer install, package links, npm ci, npm run build
bin/up <instance> --theme <dir>... [--plugin <dir>]... --activate <theme> [options]          # dev mode
bin/up <instance> --theme-zip <zip> [--child-theme-zip <zip>] [--plugin-zip <zip>]... [options]   # release mode
bin/down <instance>... | --all           # remove instances (and the network after the last one)
bin/wp [-e NAME=value]... <instance> <wp arguments>...   # WP-CLI as www-data
bin/exec [-u user] [-e NAME=value]... <instance> <command>...
bin/logs <instance> [docker logs options]...
bin/mode <instance>                      # dev or release
bin/container <instance>                 # name of the WordPress container, e.g. for docker cp
bin/tools [-w <dir>] <command>...        # PHP CLI, Composer, Node, Strauss as the host user, workspace writable
bin/e2e --instances a[,b...] --project <dir> --results <name> [-- <playwright arguments>...]
bin/run [--keep] [--skip-prepare] <pool file>...
```

Options of `bin/up` in both modes: `--object-cache valkey` (an own Valkey per instance), `--xdebug <mode>` (`XDEBUG_MODE`, default `off`), `--env NAME=value` (further environment variables of the WordPress container, e.g. `XDEBUG_CONFIG`). `bin/up` replaces an instance of the same name.

**Package links** (`bin/prepare --link`): a Composer package of a project is replaced by a relative symlink to its checkout in the workspace (`vendor/<package>` → `../../../<dir>`), so the checkout is tested instead of the locked version; lock file and `composer.json` stay untouched. `npm ci` runs only when `node_modules` is missing or older than `package-lock.json`.

## Browser tests

`bin/e2e` runs `npm run test:e2e` of a project in the official Playwright image of the project's `@playwright/test` version, in the network `wp-test-env`, with the workspace read-only. The project's Playwright configuration receives:

| Variable | Value |
|---|---|
| `WP_BASE_URLS` | the instance URLs, comma-separated |
| `WP_USERNAME`, `WP_PASSWORD` | the administrator |
| `E2E_TARGET` | `dev` or `release`, the mode of the instances (they must not mix) |
| `E2E_OUTPUT_DIR` | writable results directory, `results/<name>/` here (emptied first) |
| `PLAYWRIGHT_VERSION` | the version of the image's browsers |

The intended use is one Playwright worker per instance: `workers` equals the number of URLs, and each worker picks its URL by `TEST_PARALLEL_INDEX` (Playwright evaluates the configuration again in every worker process with that variable set; a restarted worker keeps its index). Tests of different workers then never share a site, and test files with global state (options, cron, tables) need no coordination.

## Pools

`bin/run` runs whole test setups from **pool files**: it builds the images, prepares the projects once, starts all instances in parallel, runs all pools in parallel with the pool name in front of each output line, prints the time and result of every pool and removes the instances (`--keep` leaves them running). Logs go to `results/<pool>.log`, the start of each instance to `results/_up/<instance>.log`.

```
# comments and blank lines are ignored; paths are relative to the workspace
prepare my-theme my-plugin                  # bin/prepare these projects
link vendor/library=library                 # package link for bin/prepare
tools my-theme composer release             # command in the tools image after prepare, e.g. a release build

pool theme-e2e                              # a pool; the keys below belong to it
instances 3                                 # instances theme-e2e-1 … theme-e2e-3 (default 1)
themes my-theme                             # dev mode: projects linked as themes …
plugins my-plugin                           # … and plugins
activate my-theme                           # theme to activate
object-cache valkey                         # persistent object cache
e2e my-theme                                # action: bin/e2e of the project on all instances of the pool

pool theme-release-cli
theme-zip my-theme/dist/my-theme-*.zip      # release mode; also child-theme-zip, plugin-zip (repeatable)
run my-theme/tests/cli/run {instance}       # action: command in the workspace root, {instance} replaced (instances 1)
```

A ZIP glob that matches several files takes the highest version (`sort -V`), e.g. the release a `tools` line just built; `bin/run` prints the choice. Each pool has exactly one action. Several pool files run together; pool names must be unique across them, `prepare` and `tools` lines are merged.

## Notes

- The images are built locally (`wp-test-env-wordpress`, `wp-test-env-tools`). WordPress follows the floating tag `php8.5-apache`; `bin/build --pull` updates it.
- Instances are independent of each other; how many run well at once depends on the machine. Browsers are the main cost: a Chromium worker in the block editor needs about two CPU cores.
- `state/` holds the Compose variables and release ZIPs of each running instance, `results/` the test results; both are ignored by Git.
