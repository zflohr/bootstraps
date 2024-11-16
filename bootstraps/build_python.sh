#!/usr/bin/env bash
#
# Author: Zachary Flohr

# Refer here for installing build dependencies:
# https://devguide.python.org/getting-started/setup-building/index.html#build-dependencies

readonly PYTHON_VERSION=3.13.0

usage() {
    cat <<- USAGE
Usage: ./$(basename "${0}") [OPTION...]
    
Summary:
    Purge Python, and/or install from source using the Clang compiler.

    During installation, a gzip-compressed tarball is downloaded from
    ${BASE_URL}

Package management options:
    -p | --purge    purge all locally installed versions of Python
    -i | --install  install the version of Python specified in
                    the shell parameter PYTHON_VERSION (=${PYTHON_VERSION})
                    located at the top of the script
    -r | --replace  purge all locally installed versions of Python,
                    then install the version specified in the shell
                    parameter PYTHON_VERSION (=${PYTHON_VERSION});
                    equivalent to running "./$(basename "${0}") -pi"
                    (default)

Other options:
    -h | --help     display this help text, and exit
USAGE
}

needed_binaries() {
    echo "apt-get awk curl dpkg grep lsb_release sed"
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

check_distributor_id() {
    [[ $(lsb_release --id) =~ [[:blank:]]([[:alpha:]]+)$ ]]
    case "${BASH_REMATCH[1]}" in
        'Ubuntu')
            readonly DIST_REPO_URI="archive.ubuntu.com/ubuntu"
        ;;
        'Debian')
            readonly DIST_REPO_URI="deb.debian.org/debian"
        ;;
        *)
            terminate "${BASH_REMATCH[1]}"
        ;;
    esac
}

check_root_user() {
    ! (( ${EUID} )) || terminate
}

get_clang_version() {
    local -r REGEXP='^clang-[[:digit:]]\+[[:blank:]]\+install$'
    clang_versions=($(dpkg --get-selections | grep "${REGEXP}" \
        | awk '{ print $1 }' | sort --dictionary-order))
    (( ${#clang_versions[*]} )) || check_binaries "clang"
}

define_constants() {
    readonly SOURCE_LIST="/etc/apt/sources.list"
    [[ $(lsb_release --codename) =~ [[:blank:]]([[:alpha:]]+)$ ]]
    readonly CODENAME="${BASH_REMATCH[1]}"
    readonly BASE_URL="https://www.python.org/ftp/python"
    readonly ARCHIVE=Python-${PYTHON_VERSION}.tgz
    readonly BUILD_DEP=(python3)
}

enable_source_packages() {
    local regexp="deb-src.+${DIST_REPO_URI}/? "
    regexp+="${CODENAME} ([[:alpha:]]* )*main.*"
    local -i line_number=$(grep --perl-regexp --line-number --max-count=1 \
        ".*${regexp}" ${SOURCE_LIST} | cut --delimiter=: --fields=1)
    print_source_list_progress "enable source" "${SOURCE_LIST}"
    (( ${line_number} )) &&
        sed --regexp-extended --in-place \
            "${line_number}s|.*(${regexp})|\1|" ${SOURCE_LIST} ||
        {
            regexp=$(echo ${regexp} \
                | sed --regexp-extended 's|deb-src\.\+|deb(\.\+)|')
            line_number=$(grep --perl-regexp --line-number --max-count=1 \
                ".*${regexp}" ${SOURCE_LIST} | cut --delimiter=: --fields=1)
            local -r OPTIONS=$(sed --quiet --regexp-extended \
                "${line_number}s|.*${regexp}|\1|p" ${SOURCE_LIST})
            local -r SOURCE="deb-src${OPTIONS}${DIST_REPO_URI} ${CODENAME} main"
            sed --in-place "${line_number}a\\${SOURCE}" ${SOURCE_LIST}
        }
}

download_source() {
    curl --fail --silent ${BASE_URL}/${PYTHON_VERSION}/${ARCHIVE} \
            --output ${ARCHIVE} ||
        {
            local -ir CURL_EXIT_STATUS=$?
            terminate "${ARCHIVE}" "${BASE_URL}/${PYTHON_VERSION}" \
                "${CURL_EXIT_STATUS}"
        }
}

apt_get() {
    case "${FUNCNAME[1]}" in
        'install_python')
            print_apt_progress "update"
            apt-get --quiet update || terminate "update" $?
            print_apt_progress "build-dep" "${BUILD_DEP[*]}"
            apt-get build-dep "${BUILD_DEP[@]}" || terminate "build-dep" $?
        ;;
        'purge_python')
        ;;
    esac
}

install_python() {
    local -a clang_versions
    get_clang_version
    CC=$(which "${clang_versions[-1]}")
    enable_source_packages

    #download_source
    #apt_get
}

build_pythons() {

    # Install dependencies needed to build Python natively.
    apt-get install pkg-config

    # Do a debug build if the current environment is not "production" or
    # "test", i.e., the current environment is "development" or "local".
    if [ ${ENVIRONMENT} != "production" ] && [ ${ENVIRONMENT} != "test" ]; then
        ./configure \
            CC=$(get_clang_version) \
            CFLAGS="-std=c11" \
            --prefix=/usr/local \
            --exec-prefix=/usr/local \
            --with-ensurepip=upgrade \
            --enable-optimizations \
            --with-lto=thin \
            --with-pydebug;
    else \
        ./configure \
            CC=${clang_version} \
            CFLAGS="-std=c11" \
            --prefix=/usr/local \
            --exec-prefix=/usr/local \
            --with-ensurepip=upgrade \
            --enable-optimizations \
            --with-lto=thin;
    fi
    make
    make test
}

main() {
    . ../shared/notifications.sh; check_binaries $(needed_binaries)
    . ../shared/parameters.sh; check_binaries $(needed_binaries)
    check_distributor_id; define_constants; parse_bootstrap_params $* "usage"
    unset_parameters_module; check_root_user
    unset -f check_binaries check_distributor_id \
        check_root_user define_constants usage
    if [ ${INSTALL} ]; then
        [ -z ${PURGE} ] && install_python || { purge_python && install_python; }
    else
        purge_python; [ ${PURGE} ] || install_python
    fi
}

main $*
