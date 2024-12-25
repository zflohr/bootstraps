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
    ${BASE_URL}/

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
    echo "apt-get curl dpkg grep lsb_release make sed"
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

get_package_versions() {
    local -r REGEXP="^${1}-([[:digit:]]+)[[:blank:]].*"
    local -r PACKAGE_VERSIONS=($(dpkg --get-selections \
        | sed --quiet --regexp-extended "s/${REGEXP}/\1/p" \
        | sort --numeric-sort))
    echo ${PACKAGE_VERSIONS[@]}
}

define_constants() {
    readonly PREFIX="/usr/local"
    readonly SOURCE_LIST="/etc/apt/sources.list"
    [[ $(lsb_release --codename) =~ [[:blank:]]([[:alpha:]]+)$ ]]
    readonly CODENAME="${BASH_REMATCH[1]}"
    readonly BASE_URL="https://www.python.org/ftp/python"
    readonly ARCHIVE=Python-${PYTHON_VERSION}.tgz
    readonly BUILD_DEP=(python3 build-essential gdb lcov pkg-config libbz2-dev
                        libffi-dev libgdbm-dev libgdbm-compat-dev liblzma-dev
                        libncurses5-dev libreadline6-dev libsqlite3-dev
                        libssl-dev lzma lzma-dev tk-dev uuid-dev zlib1g-dev
                        libmpdec-dev)
}

enable_source_packages() {
    local regexp="deb-src.+${DIST_REPO_URI}/? "
    regexp+="${CODENAME} ([[:alpha:]]* )*main.*"
    local entry=$(grep --perl-regexp --line-number --max-count=1 \
        "^([[:blank:]]|#.*)*${regexp}" ${SOURCE_LIST})
    deb_src_line_number=$(echo ${entry} | cut --delimiter=: --fields=1)
    if (( ${deb_src_line_number} )); then
        entry=$(echo ${entry} \
            | sed --regexp-extended 's/^[[:digit:]]+:(.*)/\1/')
        if $(echo ${entry} \
                | grep --perl-regexp --quiet "^[[:blank:]]*#.*${regexp}"); then
            print_source_list_progress "enable deb-src" "${SOURCE_LIST}"
            deb_src_entry="disabled"
            deb_src_prefix=$(sed --quiet --regexp-extended \
                "${deb_src_line_number}s|(.*)${regexp}|\1|p" ${SOURCE_LIST})
            sed --regexp-extended --in-place \
                "${deb_src_line_number}s|.*(${regexp})|\1|" ${SOURCE_LIST}
        else
            print_source_list_progress "deb-src" "${SOURCE_LIST}"
        fi
    else
        print_source_list_progress "no deb-src" "${SOURCE_LIST}"
        deb_src_entry="missing"
        regexp=$(echo ${regexp} \
            | sed --regexp-extended 's|deb-src\.\+|deb(\.\+)|')
        deb_src_line_number=$(grep --perl-regexp --line-number --max-count=1 \
            ".*${regexp}" ${SOURCE_LIST} | cut --delimiter=: --fields=1)
        local -r OPTIONS=$(sed --quiet --regexp-extended \
            "${deb_src_line_number}s|.*${regexp}|\1|p" ${SOURCE_LIST})
        local -r SOURCE="deb-src${OPTIONS}${DIST_REPO_URI} ${CODENAME} main"
        sed --in-place "${deb_src_line_number}a\\${SOURCE}" ${SOURCE_LIST}
    fi
}

restore_source_package_settings() {
    case "${deb_src_entry}" in
        'enabled')
            return
        ;;
        'disabled')
            print_source_list_progress "restore deb-src" ${SOURCE_LIST}
            sed --regexp-extended --in-place \
                "${deb_src_line_number}s|(.*)|${deb_src_prefix}\1|" \
                    ${SOURCE_LIST}
            apt_get
        ;;
        'missing')
            print_source_list_progress "restore deb-src" ${SOURCE_LIST}
            sed --in-place "$((deb_src_line_number+1))d" ${SOURCE_LIST}
            apt_get
        ;;
    esac
}

apt_get() {
    case "${FUNCNAME[1]}" in
        'build_python')
            local message
            local -i exit_status
            print_apt_progress "update"
            apt-get --quiet update || terminate "update" $?
            print_apt_progress "build-dep" "${BUILD_DEP[0]}"
            apt-get --quiet --yes build-dep "${BUILD_DEP[0]}" \
                || terminate "build-dep" $?
            print_apt_progress "install" "${BUILD_DEP[*]:1}"
            for package in "${BUILD_DEP[@]:1}"; do
                apt-get --quiet --yes install ${package} 2> stderr.tmp ||
                    {
                        exit_status=$?
                        grep "Unable to locate package ${package}" stderr.tmp &&
                        message="${package} not found. Skipping.\n" &&
                        print_message 0 "yellow" "${message}" ||
                        terminate "install" "${exit_status}"
                    }
            done
            rm stderr.tmp
            print_apt_progress "autoremove"; apt-get --quiet --yes autoremove
        ;;
        'purge_python')
        ;;
        'restore_source_package_settings')
            print_apt_progress "update"
            apt-get --quiet update || terminate "update" $?
        ;;
    esac
}

download_source() {
    print_build_progress "fetch" "${ARCHIVE}" "${BASE_URL}/${PYTHON_VERSION}/"
    curl --fail --silent ${BASE_URL}/${PYTHON_VERSION}/${ARCHIVE} \
            --output ${ARCHIVE} ||
        {
            local -ir CURL_EXIT_STATUS=$?
            terminate "${ARCHIVE}" "${BASE_URL}/${PYTHON_VERSION}/" \
                "${CURL_EXIT_STATUS}"
        }
    print_build_progress "extract" "${ARCHIVE}"
    tar --extract --file=${ARCHIVE} --gunzip; rm ${ARCHIVE}
}

configure_python() {
    local -a options=(
        --prefix=${PREFIX}
        --exec-prefix=${PREFIX}
        --with-ensurepip=upgrade
        --enable-optimizations
        --with-lto=thin)
    [[ ${ENVIRONMENT} != "production" ]] && [[ ${ENVIRONMENT} != "test" ]] &&
        options+=(--with-pydebug)
    print_build_progress "configure" "python"
    ./configure \
        CC="$(which clang-${clang_llvm_version})" \
        CPP="$(which clang-cpp-${clang_llvm_version})" \
        CXX="$(which clang++-${clang_llvm_version})" \
        CFLAGS="-std=c11" \
        LLVM_AR="$(which llvm-ar-${clang_llvm_version})" \
        LLVM_PROFDATA="$(which llvm-profdata-${clang_llvm_version})" \
        ${options[@]} || terminate "configure" "python" $?
}

install_python() {
    print_build_progress "make" "python"
    make --silent --jobs=$(nproc) || terminate "make" $?
    print_build_progress "make test"
    make --silent test || terminate "make test" $?
    print_build_progress "make altinstall" "${PREFIX}/"
    make --silent altinstall
}

binary_search() {
    local -ar ARRAY=(${@:1:$#-1})
    local -ir VAL=${@: -1}
    local -i lower=0
    upper=${#ARRAY[*]}-1
    while [[ lower -le upper ]]; do
        mid=(lower+upper)/2
        [[ ${ARRAY[mid]} -eq ${VAL} ]] && return 0
        [[ ${ARRAY[mid]} -lt ${VAL} ]] && lower=mid+1 || upper=mid-1
    done
    return 1
}

check_matching_package_versions() {
    local -i mid
    local -i upper=${#LLVM_VERSIONS[*]}-1
    for (( i=-1; ${#CLANG_VERSIONS[*]} + i + 1; i-- )); do
        binary_search ${LLVM_VERSIONS[@]:0:upper+1} ${CLANG_VERSIONS[i]}
        ! (( ${?} )) && clang_llvm_version=${CLANG_VERSIONS[i]} && return
    done
    terminate "clang" "llvm"
}

build_python() {
    local -ar LLVM_VERSIONS=($(get_package_versions llvm))
    local -ar CLANG_VERSIONS=($(get_package_versions clang))
    local -i clang_llvm_version
    (( ${#LLVM_VERSIONS[*]} )) || check_binaries "llvm"
    (( ${#CLANG_VERSIONS[*]} )) || check_binaries "clang"
    check_matching_package_versions
    local deb_src_prefix deb_src_entry="enabled"
    local -i deb_src_line_number
    enable_source_packages; apt_get; download_source
    unset -f enable_source_packages download_source
    cd Python-${PYTHON_VERSION}
    configure_python; install_python; cd ..; rm -r Python-${PYTHON_VERSION}
    restore_source_package_settings
}

main() {
    . ../shared/notifications.sh; check_binaries $(needed_binaries)
    . ../shared/parameters.sh; check_binaries $(needed_binaries)
    check_distributor_id; define_constants; parse_bootstrap_params $* "usage"
    unset_parameters_module; check_root_user
    unset -f check_distributor_id check_root_user define_constants usage
    if [ ${INSTALL} ]; then
        [ -z ${PURGE} ] && build_python || { purge_python && build_python; }
    else
        purge_python; [ ${PURGE} ] || build_python
    fi
}

main $*
