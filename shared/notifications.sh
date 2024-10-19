# Functions for printing notifications to stdout and stderr.

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
