# Author: Zachary Flohr
#
# Functions for printing terminal-dependent messages.

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
    local -i FOREGROUND_COLOR=7
    case "${2}" in
        'red')
            FOREGROUND_COLOR=1
        ;;
        'cyan')
            FOREGROUND_COLOR=6
        ;;
        'gold')
            FOREGROUND_COLOR=11
        ;;
        [[:digit:]]*)
            FOREGROUND_COLOR=${2}
        ;;
    esac
    tput sgr0 2> /dev/null                      # Turn off all attributes
    (( ${1} )) && tput rev 2> /dev/null         # Turn on reverse video mode
    tput bold 2> /dev/null                      # Turn on bold mode
    tput setaf ${FOREGROUND_COLOR} 2> /dev/null   # Set foreground color
    (( ${1} )) && echo -e ${MESSAGE} >&2 || echo -e ${MESSAGE}
    tput sgr0 2> /dev/null                      # Turn off all attributes
    return 0
}
