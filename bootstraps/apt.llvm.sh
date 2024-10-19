#!/usr/bin/env bash

readonly LLVM_VERSION=18
declare -ar LLVM_PACKAGES=(clang lldb lld)

usage() {
    cat <<- USAGE
Usage: ./$(basename "${0}") [OPTION...]
    
Summary:
    Purge and/or install LLVM packages for Debian-based Linux.

    The following LLVM tools will be purged and/or installed:
    clang: an "LLVM native" C/C++/Objective-C compiler
    lldb: a C/C++/Objective-C debugger
    lld: the LLVM linker

    Refer here for more info: https://llvm.org

Package management options:
    -p | --purge    purge all existing LLVM packages
    -i | --install  install LLVM packages for the version specified in
                    the shell parameter LLVM_VERSION (=${LLVM_VERSION})
                    located at the top of the script
    -r | --replace  purge all existing LLVM packages, then install the
                    version specified in the shell parameter
                    LLVM_VERSION (=${LLVM_VERSION}); equivalent to
                    running "./$(basename "${0}") -pi" (default)

Other options:
    -h | --help     display this help text, and exit
USAGE
}

terminate() {
    local error_msg
    local -i exit_status=1
    case "${FUNCNAME[1]}" in
        'check_binaries')
            error_msg="You must install the following \
                tools to run this script: ${1}"
        ;;
        'check_conflicting_args')
            error_msg="Illegal combination of options: ${1}"
        ;;
        'check_root_user')
            error_msg="This script must be run as root!"
        ;;
        'parse_args')
            error_msg="Terminating..."
            exit_status=${1}
        ;;
        'install_llvm')
            case "${1}" in
                'key')
                    error_msg="Could not download the OpenPGP \
                        public key from ${2}\nTerminating..."
                    exit_status=${3}
                ;;
                'update')
                    error_msg="\"apt-get update\" failed!\nTerminating..."
                    exit_status=${2}
                ;;
            esac
        ;;
        *)
            error_msg="Something went wrong. Terminating..."
        ;;
    esac
    print_message 1 "red" "${error_msg}"
    exit ${exit_status}
}

check_binaries() {
    local -a needed_binaries missing_binaries=()
    which which &> /dev/null || terminate "which"
    needed_binaries=(apt-get awk dpkg getopt gpg grep lsb_release sed wget)
    for binary in "${needed_binaries[@]}"; do
        which ${binary} &> /dev/null || missing_binaries+=($binary)
    done
    [ ${#missing_binaries[@]} -eq 0 ] || terminate "${missing_binaries[*]}"
}

check_conflicting_args() {
    local conflicting_opts
    if [ ${replace} ]; then {
        [ ${install} ] && conflicting_opts="-r|--replace, -i|--install"
    } || {
        [ -z ${purge} ] || conflicting_opts="-r|--replace, -p|--purge"
    }
    fi
    [ -z "${conflicting_opts}" ] || terminate "${conflicting_opts}"
}

parse_args() {
    local temp
    local -i getopt_exit_status
    temp=$(getopt -o 'hipr' -l 'help,install,purge,replace' \
        -n $(basename "${0}") -- "$@")
    getopt_exit_status=$?
    [ ${getopt_exit_status} -ne 0 ] && terminate ${getopt_exit_status}
    eval set -- "${temp}"
    unset temp
    while true; do
        case "$1" in
            '-h'|'--help')
                usage
                exit 0
            ;;
            '-i'|'--install')
                [ -z ${install} ] && readonly install="yes"
                shift
            ;;
            '-p'|'--purge')
                [ -z ${purge} ] && readonly purge="yes"
                shift
            ;;
            '-r'|'--replace')
                [ -z ${replace} ] && readonly replace="yes"
                shift
            ;;
            '--')
                shift
                break
            ;;
        esac
        check_conflicting_args
    done
    [ $# -eq 0 ] || { usage >&2 && exit 1; }
}

check_root_user() {
    [ ${EUID} -eq 0 ] || terminate
}

define_constants() {
    readonly BASE_URL="https://apt.llvm.org"
    readonly PPA_DIR="/etc/apt/sources.list.d/"
    readonly GPG_DIR="/usr/share/keyrings/"
    readonly GPG_PATH="/llvm-snapshot.gpg.key"
    readonly LLVM_GPG_BASENAME="llvm.gpg"
    [[ $(lsb_release -c) =~ [[:blank:]]([[:alpha:]]+)$ ]]
    readonly CODENAME="${BASH_REMATCH[1]}"
    readonly LLVM_SOURCE_FILE="llvm.list"
    readonly TYPE="deb"
    readonly OPTIONS="[arch=amd64 signed-by=${GPG_DIR}${LLVM_GPG_BASENAME}]"
    readonly URI="${BASE_URL}/${CODENAME}/"
    readonly SUITE="llvm-toolchain-${CODENAME}-${LLVM_VERSION}"
    readonly COMPONENTS="main"
    readonly REPO="${TYPE} ${OPTIONS} ${URI} ${SUITE} ${COMPONENTS}"
}

print_apt_progress() {
    local progress_msg="\nRunning apt-get ${1}..."
    case "${1}" in
        'install')
            progress_msg+="\nInstalling the following packages: \
                ${install_pkgs[*]}"
        ;;
        'purge')
            progress_msg+="\nPurging the following packages: ${purge_pkgs[*]}"
        ;;
    esac
    print_message 0 "cyan" "${progress_msg}"
}

print_source_list_progress() {
    local progress_msg
    case "${1}" in
        'key found')
            progress_msg="\nFound OpenPGP public key in ${GPG_DIR}"
        ;;
        'no key')
            progress_msg="\nAdded OpenPGP public key from \
                ${BASE_URL}${GPG_PATH} to ${GPG_DIR}"
        ;;
        'remove key')
            progress_msg="\nRemoved OpenPGP public key from ${GPG_DIR}"
        ;;
        'source found')
            progress_msg="\nFound entry in ${PPA_DIR}${LLVM_SOURCE_FILE}"
        ;;
        'no source')
            progress_msg="\nAdded entry to ${PPA_DIR}${LLVM_SOURCE_FILE}"
        ;;
        'remove source')
            progress_msg="\nRemoved ${PPA_DIR}${LLVM_SOURCE_FILE}"
        ;;
    esac
    print_message 0 "cyan" "${progress_msg}"
}

install_llvm() {
    local -a install_pkgs=()
    local -i wget_exit_status
    install_pkgs+=($(echo "${LLVM_PACKAGES[@]}" \
        | sed "s/\([a-z]\+\)/\1-${LLVM_VERSION}/g"))
    if [ -f "${GPG_DIR}${LLVM_GPG_BASENAME}" ]; then
        print_source_list_progress "key found"
    else
        {
            wget -qO ${GPG_DIR}${LLVM_GPG_BASENAME} ${BASE_URL}${GPG_PATH} &&
                cat ${GPG_DIR}${LLVM_GPG_BASENAME} \
                    | gpg --yes -o ${GPG_DIR}${LLVM_GPG_BASENAME} --dearmor &&
                chmod 0644 ${GPG_DIR}${LLVM_GPG_BASENAME} &&
                print_source_list_progress "no key"
        } || {
            wget_exit_status=$?
            rm ${GPG_DIR}${LLVM_GPG_BASENAME}
            terminate "key" "${BASE_URL}${GPG_PATH}" "${wget_exit_status}"
        }
    fi
    grep -qsF "${REPO}" "${PPA_DIR}${LLVM_SOURCE_FILE}" &&
        print_source_list_progress "source found" ||
        {
            bash -c "echo ${REPO} >> ${PPA_DIR}${LLVM_SOURCE_FILE}"
            print_source_list_progress "no source"
        }
   print_apt_progress "update"; apt-get -q update || terminate "update" $?
   print_apt_progress "install"; apt-get -yq install "${install_pkgs[@]}"
   print_apt_progress "autoremove"; apt-get -yq autoremove
}

purge_llvm() {
    local -a purge_pkgs=()
    local regexp='-[[:digit:]]\\+[[:blank:]]\\+install$\\|'
    regexp=$(echo "${LLVM_PACKAGES[*]}" | sed "s/\([a-z]\+\)/^\1${regexp}/g" \
        | sed 's/ //g')
    purge_pkgs+=($(dpkg --get-selections | grep -o "${regexp}" \
        | awk '{ print $1 }' | paste -s -d ' '))
    [ -f "${PPA_DIR}${LLVM_SOURCE_FILE}" ] &&
        rm ${PPA_DIR}${LLVM_SOURCE_FILE} &&
        print_source_list_progress "remove source"
    [ -f "${GPG_DIR}${LLVM_GPG_BASENAME}" ] &&
        rm ${GPG_DIR}${LLVM_GPG_BASENAME} &&
        print_source_list_progress "remove key"
    [ ${#purge_pkgs[@]} -eq 0 ] || {
        print_apt_progress "purge"; apt-get -yq purge "${purge_pkgs[@]}"
        print_apt_progress "autoremove"; apt-get -yq autoremove
        print_apt_progress "autoclean"; apt-get -yq autoclean
    }
}

main() {
    local install purge replace
    . ../shared/notifications.sh
    check_binaries; parse_args $*; check_root_user; define_constants
    unset -f usage check_binaries parse_args define_constants \
        check_root_user check_conflicting_args
    if [ ${install} ]; then
        [ -z ${purge} ] && install_llvm || { purge_llvm && install_llvm; }
    else
        purge_llvm; [ ${purge} ] || install_llvm
    fi
}

main $*
