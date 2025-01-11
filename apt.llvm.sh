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

needed_binaries() {
    echo "apt-get awk dpkg gpg grep lsb_release sed wget"
}

check_binaries() {
    local -a missing_binaries=()
    local -ar NEEDED_BINARIES=($*)
    which which &> /dev/null || terminate "which"
    for binary in "${NEEDED_BINARIES[@]}"; do
        which ${binary} &> /dev/null || missing_binaries+=($binary)
    done
    ! (( ${#missing_binaries[*]} )) || terminate "${missing_binaries[*]}"
}

check_root_user() {
    ! (( ${EUID} )) || terminate
}

define_constants() {
    readonly ARCH=$(dpkg --print-architecture)
    readonly BASE_URL="https://apt.llvm.org"
    readonly PPA_DIR="/etc/apt/sources.list.d/"
    readonly GPG_DIR="/usr/share/keyrings/"
    readonly GPG_PATH="/llvm-snapshot.gpg.key"
    readonly LLVM_GPG_BASENAME="llvm.gpg"
    [[ $(lsb_release --codename) =~ [[:blank:]]([[:alpha:]]+)$ ]]
    readonly CODENAME="${BASH_REMATCH[1]}"
    readonly LLVM_SOURCE_FILE="llvm.list"
    readonly TYPE="deb"
    readonly OPTIONS="[arch=${ARCH} signed-by=${GPG_DIR}${LLVM_GPG_BASENAME}]"
    readonly URI="${BASE_URL}/${CODENAME}/"
    readonly SUITE="llvm-toolchain-${CODENAME}-${LLVM_VERSION}"
    readonly COMPONENTS="main"
    readonly REPO="${TYPE} ${OPTIONS} ${URI} ${SUITE} ${COMPONENTS}"
}

download_public_key() {
    wget --quiet --output-document="${GPG_DIR}${LLVM_GPG_BASENAME}" \
            ${BASE_URL}${GPG_PATH} &&
        cat ${GPG_DIR}${LLVM_GPG_BASENAME} \
            | gpg --yes --output "${GPG_DIR}${LLVM_GPG_BASENAME}" --dearmor &&
        chmod 0644 ${GPG_DIR}${LLVM_GPG_BASENAME} &&
        print_public_key_progress "no key" "${BASE_URL}${GPG_PATH}" \
            "${GPG_DIR}" ||
        {
            local -ir WGET_EXIT_STATUS=$? &&
            rm ${GPG_DIR}${LLVM_GPG_BASENAME} &&
            terminate "${BASE_URL}${GPG_PATH}" "${WGET_EXIT_STATUS}"
        }
}

apt_get() {
    case "${FUNCNAME[1]}" in
        'install_llvm')
            print_apt_progress "update"
            apt-get --quiet update || terminate "update" $?
            print_apt_progress "install" "${INSTALL_PKGS[*]}"
            apt-get --quiet --yes install "${INSTALL_PKGS[@]}" ||
                terminate "install" $?
            print_apt_progress "autoremove"; apt-get --quiet --yes autoremove
        ;;
        'purge_llvm')
            print_apt_progress "purge" "${PURGE_PKGS[*]}"
            apt-get --quiet --yes purge "${PURGE_PKGS[@]}"
            print_apt_progress "autoremove"; apt-get --quiet --yes autoremove
            print_apt_progress "autoclean"; apt-get --quiet --yes autoclean
        ;;
    esac
}

install_llvm() {
    local -ar INSTALL_PKGS=($(echo "${LLVM_PACKAGES[@]}" \
        | sed --regexp-extended "s/([a-z]+)/\1-${LLVM_VERSION}/g"))
    if [ -f "${GPG_DIR}${LLVM_GPG_BASENAME}" ]; then
        print_public_key_progress "key found" "${GPG_DIR}"
    else
        download_public_key
    fi
    grep --quiet --no-messages --fixed-strings "${REPO}" \
            "${PPA_DIR}${LLVM_SOURCE_FILE}" &&
        print_source_list_progress "source found" \
            "${PPA_DIR}${LLVM_SOURCE_FILE}" ||
        {
            bash -c "echo ${REPO} >> ${PPA_DIR}${LLVM_SOURCE_FILE}"
            print_source_list_progress "no source" \
                "${PPA_DIR}${LLVM_SOURCE_FILE}"
        }
    apt_get
}

purge_llvm() {
    local regexp='-[[:digit:]]+[[:blank:]]+install$|'
    regexp=$(echo "${LLVM_PACKAGES[*]}" \
        | sed --regexp-extended "s/([a-z]+)/^\1${regexp}/g" | sed 's/ //g')
    local -ar PURGE_PKGS=($(dpkg --get-selections | \
        grep --perl-regexp --only-matching "${regexp}" | awk '{ print $1 }'))
    [ -f "${PPA_DIR}${LLVM_SOURCE_FILE}" ] &&
        rm ${PPA_DIR}${LLVM_SOURCE_FILE} &&
        print_source_list_progress "remove source" \
            "${PPA_DIR}${LLVM_SOURCE_FILE}"
    [ -f "${GPG_DIR}${LLVM_GPG_BASENAME}" ] &&
        rm ${GPG_DIR}${LLVM_GPG_BASENAME} &&
        print_public_key_progress "remove key" "${GPG_DIR}"
    ! (( ${#PURGE_PKGS[@]} )) || apt_get
}

main() {
    . shared/notifications.sh; check_binaries $(needed_binaries)
    . shared/parameters.sh; check_binaries $(needed_binaries)
    parse_bootstrap_params $* "usage"; unset_parameters_module
    check_root_user; define_constants
    unset -f usage check_binaries define_constants check_root_user
    if [ ${INSTALL} ]; then
        [ -z ${PURGE} ] && install_llvm || { purge_llvm && install_llvm; }
    else
        purge_llvm; [ ${PURGE} ] || install_llvm
    fi
}

main $*
