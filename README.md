# bootstraps

These are Bash scripts for downloading, configuring, and installing software
from source or for adding third-party repositories and their OpenPGP public keys
to the APT package management system on Debian-family systems. All scripts
require superuser privileges. For scripts that add third-party repositories to
APT, sources are added to `/etc/apt/sources.list.d/` and public keys are added
to `/usr/share/keyrings/`.

## Usage

Invoke a script with the `-h|--help` option to display a brief summary of the
program and a usage synopsis. 

## Contributing

This is not an open source project. I've made the repository public mainly to
evidence my skills in Bash, common GNU utilities, shell-scripting fundamentals,
and workflow automation.
