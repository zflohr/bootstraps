# Author: Zachary Flohr
#
# Functions for printing terminal-dependent messages and for shell
# exiting.

########################################################################
# Print a colorized message to stdout or stderr.
# Arguments:
#   1: An integer, which indicates to which data stream to send the
#      message: zero for stdout, non-zero for stderr.
#   2: The foreground color for the message. The color may be a name or
#      an integer. If an integer, it will be the argument to the
#      "setaf" terminal capability. 
#   3: A message to print.
# Outputs:
#   Writes $3 to stdout if $1 is zero.
#   Writes $3 to stderr if $1 is non-zero.
# Returns:
#   0
########################################################################
print_message() {
    local -r MESSAGE="\n${3}"
    local -i foreground_color=7
    case "${2}" in
        'red')
            foreground_color=1
        ;;
        'cyan')
            foreground_color=6
        ;;
        'gold')
            foreground_color=11
        ;;
        [[:digit:]]*)
            foreground_color=${2}
        ;;
    esac
    tput sgr0 2> /dev/null                          # Turn off all attributes
    (( ${1} )) && tput rev 2> /dev/null             # Turn on reverse video mode
    tput bold 2> /dev/null                          # Turn on bold mode
    tput setaf ${foreground_color} 2> /dev/null     # Set foreground color
    (( ${1} )) && echo -e ${MESSAGE} >&2 || echo -e ${MESSAGE}
    tput sgr0 2> /dev/null                          # Turn off all attributes
    return 0
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
        'download_public_key')
            error_msg="Could not download the OpenPGP \
                public key from ${1}\nTerminating..."
            exit_status=${2}
        ;;
        'apt_get')
            error_msg="\"apt-get ${1}\" failed!\nTerminating..."
            exit_status=${2}
        ;;
        *)
            error_msg="Something went wrong. Terminating..."
        ;;
    esac
    print_message 1 "red" "${error_msg}"
    exit ${exit_status}
}

