# shellcheck shell=bash
# lib/ui.sh - User interface helpers

# Color codes (disabled if NO_COLOR is set or not a terminal)
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 2 ]]; then
    _RED=$'\033[0;31m'
    _YELLOW=$'\033[0;33m'
    _GREEN=$'\033[0;32m'
    _CYAN=$'\033[0;36m'
    _BOLD=$'\033[1m'
    _RESET=$'\033[0m'
else
    _RED=""
    _YELLOW=""
    _GREEN=""
    _CYAN=""
    _BOLD=""
    _RESET=""
fi

# Log an informational message
log_info() {
    echo "${_CYAN}${*}${_RESET}"
}

# Log a success message
log_success() {
    echo "${_GREEN}${*}${_RESET}"
}

# Log a warning message to stderr
log_warn() {
    echo "${_YELLOW}Warning:${_RESET} ${*}" >&2
}

# Log an error message to stderr
log_error() {
    echo "${_RED}Error:${_RESET} ${*}" >&2
}

# Log an error and exit
die() {
    log_error "$@"
    exit 1
}

# Print a message only if VERBOSE is true
# Usage: verbose "Running command: $cmd"
verbose() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo "${_BOLD}▸${_RESET} ${*}" >&2
    fi
}

# Run a command, showing it first if VERBOSE is true
# Usage: run_verbose git push ...
run_verbose() {
    verbose "$*"
    "$@"
}

# Prompt for yes/no confirmation
# Returns 0 for yes, 1 for no
# Respects FORCE flag (auto-yes)
confirm() {
    local prompt="${1:-Continue?}"

    if [[ "${FORCE:-false}" == "true" ]]; then
        return 0
    fi

    # If not a terminal, default to no
    if [[ ! -t 0 ]]; then
        return 1
    fi

    local response
    read -r -p "${prompt} [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Print a section header
section() {
    echo ""
    echo "${_BOLD}${*}${_RESET}"
    echo ""
}

# Print a list item
list_item() {
    echo "  • ${*}"
}

# Print a key-value pair
kv() {
    local key="$1"
    local value="$2"
    printf "  ${_BOLD}%-20s${_RESET} %s\n" "$key:" "$value"
}

# Show a simple spinner while a command runs (for long operations)
# Usage: with_spinner "Pushing..." git push
with_spinner() {
    local message="$1"
    shift

    # If not a terminal or verbose mode, just run the command
    if [[ ! -t 2 ]] || [[ "${VERBOSE:-false}" == "true" ]]; then
        verbose "$*"
        "$@"
        return $?
    fi

    # Show message
    printf "%s " "$message" >&2

    # Run command in background
    "$@" &
    local pid=$!

    # Spinner characters
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r%s %s" "$message" "${spin:i++%${#spin}:1}" >&2
        sleep 0.1
    done

    # Get exit status
    wait "$pid"
    local status=$?

    # Clear spinner
    printf "\r%s   \r" "$message" >&2

    if [[ $status -eq 0 ]]; then
        printf "%s ${_GREEN}✓${_RESET}\n" "$message" >&2
    else
        printf "%s ${_RED}✗${_RESET}\n" "$message" >&2
    fi

    return $status
}

# Check if we're in dry-run mode
is_dry_run() {
    [[ "${DRY_RUN:-false}" == "true" ]]
}

# Run a command, or just print it if dry-run
# Usage: maybe_run git push ...
maybe_run() {
    if is_dry_run; then
        echo "${_CYAN}[dry-run]${_RESET} $*"
        return 0
    fi
    "$@"
}
