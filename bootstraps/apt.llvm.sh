#!/usr/bin/env bash
#
# Author: Zachary Flohr

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
                ${INSTALL_PKGS[*]}"
        ;;
        'purge')
            progress_msg+="\nPurging the following packages: ${PURGE_PKGS[*]}"
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

download_public_key() {
    wget -qO ${GPG_DIR}${LLVM_GPG_BASENAME} ${BASE_URL}${GPG_PATH} &&
        cat ${GPG_DIR}${LLVM_GPG_BASENAME} \
            | gpg --yes -o ${GPG_DIR}${LLVM_GPG_BASENAME} --dearmor &&
        chmod 0644 ${GPG_DIR}${LLVM_GPG_BASENAME} &&
        print_source_list_progress "no key" ||
        {
            local -ir WGET_EXIT_STATUS=$? &&
            rm ${GPG_DIR}${LLVM_GPG_BASENAME} &&
            terminate "${BASE_URL}${GPG_PATH}" "${WGET_EXIT_STATUS}"
        }
}

apt_get() {
    case "${FUNCNAME[1]}" in
        'install_llvm')
            print_apt_progress "update";
            apt-get -q update || terminate "update" $?
            print_apt_progress "install";
            apt-get -yq install "${INSTALL_PKGS[@]}" || terminate "install" $?
            print_apt_progress "autoremove"; apt-get -yq autoremove
        ;;
        'purge_llvm')
            print_apt_progress "purge"; apt-get -yq purge "${PURGE_PKGS[@]}"
            print_apt_progress "autoremove"; apt-get -yq autoremove
            print_apt_progress "autoclean"; apt-get -yq autoclean
        ;;
    esac
}

install_llvm() {
    local -ar INSTALL_PKGS=($(echo "${LLVM_PACKAGES[@]}" \
        | sed "s/\([a-z]\+\)/\1-${LLVM_VERSION}/g"))
    if [ -f "${GPG_DIR}${LLVM_GPG_BASENAME}" ]; then
        print_source_list_progress "key found"
    else
        download_public_key
    fi
    grep -qsF "${REPO}" "${PPA_DIR}${LLVM_SOURCE_FILE}" &&
        print_source_list_progress "source found" ||
        {
            bash -c "echo ${REPO} >> ${PPA_DIR}${LLVM_SOURCE_FILE}"
            print_source_list_progress "no source"
        }
    apt_get
}

purge_llvm() {
    local regexp='-[[:digit:]]\\+[[:blank:]]\\+install$\\|'
    regexp=$(echo "${LLVM_PACKAGES[*]}" | sed "s/\([a-z]\+\)/^\1${regexp}/g" \
        | sed 's/ //g')
    local -ar PURGE_PKGS=($(dpkg --get-selections | grep -o "${regexp}" \
        | awk '{ print $1 }' | paste -s -d ' '))
    [ -f "${PPA_DIR}${LLVM_SOURCE_FILE}" ] &&
        rm ${PPA_DIR}${LLVM_SOURCE_FILE} &&
        print_source_list_progress "remove source"
    [ -f "${GPG_DIR}${LLVM_GPG_BASENAME}" ] &&
        rm ${GPG_DIR}${LLVM_GPG_BASENAME} &&
        print_source_list_progress "remove key"
    ! (( ${#PURGE_PKGS[@]} )) || apt_get
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
