#!/usr/bin/env bash
#
# Author: Zachary Flohr

# Refer here for installing build dependencies:
# https://devguide.python.org/getting-started/setup-building/index.html#build-dependencies

readonly PYTHON_VERSION=3.12.5

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
    echo "apt-get awk dpkg grep"
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

get_clang_version() {
    local regexp='^clang-[[:digit:]]\+[[:blank:]]\+install$'
    clang_versions=($(dpkg --get-selections | grep "${regexp}" \
        | awk '{ print $1 }' | sort -d))
    (( ${#clang_versions[*]} )) || check_binaries "clang"
}

define_constants() {
    readonly BASE_URL="https://www.python.org/ftp/python"
    readonly ARCHIVE=Python-${PYTHON_VERSION}.tgz
}

build_python() {
    local -a clang_versions
    get_clang_version
    CC=$(which "${clang_versions[-1]}")
    echo $CC
}

build_pythons() {
    get_clang_version
    curl ${BASE_URL}/${PYTHON_VERSION}/${ARCHIVE} -o ${ARCHIVE}
    apt-get update

    # Install dependencies needed to build Python natively.
    apt-get build-dep python3
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
    define_constants; parse_bootstrap_params $* "usage";
    unset_parameters_module; check_root_user
    build_python
    unset -f usage check_binaries define_constants check_root_user
}

main $*
