#!/bin/bash
### (C) Chronon Systems, Inc. 2017
# All rights reserved
# DripStat Infra Agent installation script - installs the DripStat Infra Agent on supported Linux distros

# Halt on error
set -e

### Global variables

distro=""
version=""
arch=""
family=""

### Sudo handling

if [[ $EUID -eq 0 ]]; then
	sudo_cmd=''											# The script is being executed by root
else
	sudo_cmd='sudo'
fi

### Method declarations

# Method used to print out the help/usage message
#
usage() {
	echo "Usage: " 											# TODO: Finalize the usage message
	exit 1
}

# Method to report an error and exit the script
#
complain() {
	printf "\033[91m\n* ${1}. Quitting.\n\033[0m\n"
	exit 2
}

# Method used for printing progress info messages (in color)
#
progressMsg() {
	printf "\033[92m\n* ${1}.\n\033[0m\n"
}

# Method that's checking the necessary pre-requisites and exits the script if not all are met
#
prereq_check() {
	if [ -z "${DS_LIC}" ]; then
		complain "DS_LIC variable not set"
	fi
}

# Method used for detecting OS, version and system architecture
#
detect_os() {
    	# Inspired by
	# https://unix.stackexchange.com/questions/6345/how-can-i-get-distribution-name-and-version-number-in-a-simple-shell-script

	release_file="/etc/os-release"
	if [[ ! -f "${release_file}" ]]; then
		release_file="/usr/lib/os-release"
	fi

	if [ -f "${release_file}" ]; then
		# freedesktop.org and systemD
		. "${release_file}"
		distro=$ID
		version=$VERSION_ID
	elif type lsb_release >/dev/null 2>&1; then
		# linuxbase.org
		distro=$(lsb_release -si)
		version=$(lsb_release -sr)
	elif [ -f /etc/lsb-release ]; then
		# For some versions of Debian/Ubuntu without lsb_release command
		. /etc/lsb-release
		distro=$DISTRIB_ID
		version=$DISTRIB_RELEASE
	elif [ -f /etc/debian_version ]; then
		# Older Debian/Ubuntu/etc.
		distro=debian
		version=$(cat /etc/debian_version)
	elif [ -f /etc/redhat-release ]; then
		# Older Red Hat, CentOS, etc.
		distro=redhat
		version=$(cat /etc/redhat-release)
	else
	    	complain "Unable to detect your linux distribution"
	fi

	distro=$(echo ${distro} | awk '{print tolower($1)}')						# Take only the first word and put it to lowercase
	version=$(echo ${version} | sed 's/\.[0-9]*.*//' | sed 's/[^0-9]//g')				# Discard the minor version number and all the non-number chars

	case $(uname -m) in
		x86_64)
			arch=x86_64 									# 64-bit architecture
			;;
		i*86)
			arch=i386  									# 32-bit architecture
			;;
		*)
			complain "Unable to detect system architecture"
			;;
	esac

	case ${distro} in
		amzn | amazon)
			distro=redhat									# Amazon Linux has identical install commands with RH6
			version=6
			;;
		centos)
			distro=redhat									# CentOS has identical install commands with RH
			;;
	esac

	case ${distro} in
		ubuntu | debian)
			family=debian
			;;
		redhat)
			family=redhat
			;;
		*)
			complain "Unsupported or unknown linux distribution"
			;;
	esac
}

# Preparation of the repository
#
repo_setup() {
	case $family in
		debian)
		    progressMsg "Installing apt-transport-https"
			${sudo_cmd} apt-get update
			${sudo_cmd} apt-get install -y apt-transport-https

			suffix=""									# apt repo suffix
			case ${distro}+${version} in
				ubuntu+1[2-4])								# Ubuntu 15+ needs ""
					suffix="-upstart"
					;;
				debian+7)								# Debian 8+ needs ""
					suffix="-sysv"
					;;
			esac

			repo_file="/etc/apt/sources.list.d/dripstat.list"
			if [ ! -f ${repo_file} ]; then
				${sudo_cmd} sh -c "echo \"deb https://apt.dripstat.com/ dripstat${suffix} non-free\" > ${repo_file}"
			fi
			${sudo_cmd} sh -c "wget -O- https://apt.dripstat.com/key/public.gpg | apt-key add -"
			${sudo_cmd} apt-get update
			;;
		redhat)
		    	repo_file="/etc/yum.repos.d/dripstat-infra.repo"
			if [ ! -f "${repo_file}" ]; then
				${sudo_cmd} curl -o "${repo_file}" https://yum.dripstat.com/infraagent/el/${version}/${arch}/dripstat-infra.repo
			fi
			${sudo_cmd} yum makecache -y
			;;
	esac
}

# Package installation
#
install() {
	case $family in
		debian)
			${sudo_cmd} apt-get install dripstat-infra -y
			;;
		redhat)
			${sudo_cmd} yum install dripstat-infra -y
			;;
	esac
}

# License activation
#
license_activation() {
	config_file="/etc/dripstat-infra/config.toml"

 	if [ -f "${config_file}" ]; then
		progressMsg "${config_file} file already exists, not touching it"
	else
		${sudo_cmd} sh -c "sed \"s/licenseKey.*/licenseKey = '${DS_LIC}'/\" /etc/dripstat-infra/config.toml.example > ${config_file}"
		progressMsg "License key added to ${config_file}"
	fi
}

# Method for starting up the service
#
startup() {
	case $distro+$version in
		ubuntu+1[2-4] | redhat+6)
			${sudo_cmd} initctl start dripstat-infra
			;;
		debian+7)
			${sudo_cmd} /etc/init.d/dripstat-infra start
			;;
		*)											# Ubuntu 15+, Debian 8+ and RH7+ use systemD
			${sudo_cmd} systemctl start dripstat-infra
			;;
	esac
}

# Run the individual steps

progressMsg "Checking pre-requisites"
prereq_check
progressMsg "Detecting OS"
detect_os
progressMsg "Adding dripstat repository"
repo_setup
progressMsg "Installing dripstat-infra"
install
progressMsg "Activating license"
license_activation
progressMsg "Starting-up the agent"
startup
progressMsg "All done. Your server is now dripping!"

# Restore environment
set +e

# Return success
exit 0
