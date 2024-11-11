. "$(dirname ${BASH_SOURCE[0]})/notifications.sh"

check_conflicting_bootstrap_params() {
    local conflicting_opts
    if [ ${REPLACE} ]; then {
        [ ${INSTALL} ] && conflicting_opts="-r|--replace, -i|--install"
    } || {
        [ -z ${PURGE} ] || conflicting_opts="-r|--replace, -p|--purge"
    }
    fi
    [ -z "${conflicting_opts}" ] || terminate "${conflicting_opts}"
}

parse_bootstrap_params() {
    local temp
    local -r USAGE=${!#}
    temp=$(getopt -o 'hipr' -l 'help,install,purge,replace' \
        -n $(basename "${0}") -- "${@:1:$#-1}")
    local -i getopt_exit_status=$?
    (( ${getopt_exit_status} )) && terminate ${getopt_exit_status}
    eval set -- "${temp}"
    unset temp
    while true; do
        case "$1" in
            '-h'|'--help')
                eval ${USAGE}
                exit 0
            ;;
            '-i'|'--install')
                [ -z ${INSTALL} ] && readonly INSTALL="yes"
                shift
            ;;
            '-p'|'--purge')
                [ -z ${PURGE} ] && readonly PURGE="yes"
                shift
            ;;
            '-r'|'--replace')
                [ -z ${REPLACE} ] && readonly REPLACE="yes"
                shift
            ;;
            '--')
                shift
                break
            ;;
        esac
        check_conflicting_bootstrap_params
    done
    ! (( $# )) || { eval ${USAGE} >&2 && exit 1; }
}

needed_binaries() {
    echo "getopt"
}

unset_parameters_module() {
    unset -f check_conflicting_bootstrap_params parse_bootstrap_params \
        needed_binaries unset_parameters_module
}
