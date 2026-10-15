# Shared functions and constants of the bin/ scripts; sourced, never executed.
# shellcheck shell=bash
# shellcheck disable=SC2034 # the constants are used by the scripts that source this file

WP_TEST_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The workspace is the parent directory: the projects live next to this repository.
WORKSPACE_DIR="$(cd "${WP_TEST_ENV_DIR}/.." && pwd)"
STATE_DIR="${WP_TEST_ENV_DIR}/state"
RESULTS_DIR="${WP_TEST_ENV_DIR}/results"

# Shared Docker network of all instances and test runners.
NETWORK=wp-test-env
WORDPRESS_IMAGE=wp-test-env-wordpress
TOOLS_IMAGE=wp-test-env-tools
# Published images (.github/workflows/images.yml), tagged with the hash of their docker/ directory.
REGISTRY=ghcr.io/saijsaij
TOOLS_CACHE_VOLUME=wp-test-env-tools-cache

# Every instance has the same administrator; instances are reachable only on the Docker network.
ADMIN_USER='admin'
ADMIN_PASSWORD='password'
ADMIN_EMAIL=admin@example.com

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

# check_instance_name <instance>: a DNS label, also usable in Compose project names.
check_instance_name() {
    if [[ ! "$1" =~ ^[a-z0-9]([a-z0-9-]{0,48}[a-z0-9])?$ ]]; then
        fail "invalid instance name '$1'; expected lowercase letters, digits and inner hyphens (at most 50 characters)."
    fi
}

instance_host() {
    echo "$1.test"
}

instance_url() {
    echo "http://$(instance_host "$1")"
}

instance_state() {
    echo "${STATE_DIR}/$1"
}

instance_container() {
    echo "wp-test-env-$1"
}

instance_project() {
    echo "wp-test-env-$1"
}

# require_instance <instance>: the instance was started by bin/up and its WordPress container runs.
require_instance() {
    check_instance_name "$1"
    if [[ ! -f "$(instance_state "$1")/mode" ]]; then
        fail "instance '$1' is unknown; start it with bin/up $1 …"
    fi
    if [[ "$(docker inspect --format '{{.State.Running}}' "$(instance_container "$1")" 2>/dev/null)" != "true" ]]; then
        fail "instance '$1' is not running (container $(instance_container "$1")); start it again with bin/up."
    fi
}

# instance_mode <instance>: dev or release.
instance_mode() {
    cat "$(instance_state "$1")/mode"
}

# instance_compose <instance> <compose arguments>...: docker compose for the instance's project.
instance_compose() {
    local instance="$1" state files
    shift
    state="$(instance_state "${instance}")"
    files=(-f "${WP_TEST_ENV_DIR}/compose.yaml")
    if [[ "$(instance_mode "${instance}")" == "dev" ]]; then
        files+=(-f "${WP_TEST_ENV_DIR}/compose.dev.yaml")
    fi
    docker compose --progress quiet -p "$(instance_project "${instance}")" --env-file "${state}/compose.env" "${files[@]}" "$@"
}

# ensure_network: creates the shared network; tolerates a parallel bin/up creating it at the same time.
ensure_network() {
    if docker network inspect "${NETWORK}" >/dev/null 2>&1; then
        return
    fi
    if ! docker network create "${NETWORK}" >/dev/null 2>&1; then
        docker network inspect "${NETWORK}" >/dev/null 2>&1 || fail "cannot create the Docker network ${NETWORK}."
    fi
}

# docker_tty_flags: -t only when both stdin and stdout are terminals (keeps output streams apart in scripts).
docker_tty_flags() {
    if [[ -t 0 && -t 1 ]]; then
        echo "-it"
    else
        echo "-i"
    fi
}

# image_hash <wordpress|tools>: hash of the files, paths and modes in docker/<image>/, the tag of the published image.
image_hash() {
    local directory="${WP_TEST_ENV_DIR}/docker/$1"
    [[ -d "${directory}" ]] || fail "unknown image '$1'."
    (
        cd "${directory}" || exit 1
        find . -type f -printf '%m %p\n' | LC_ALL=C sort
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
    ) | sha256sum | cut -c1-16
}

# image_ref <wordpress|tools>: the published image matching the current docker/<image>/.
image_ref() {
    echo "${REGISTRY}/wp-test-env-$1:$(image_hash "$1")"
}
