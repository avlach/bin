#!/bin/bash

# Static config variables
vpn_host=uobnet.bris.ac.uk
vpn_port=443
vpn_realm=UoB-Users

# Generate temporary files:
uobnet_out=$(mktemp --suffix=.out) || { echo "Failed to create temp file" ; exit 1; }
uobnet_err=$(mktemp --suffix=.err) || { echo "Failed to create temp file" ; exit 1; }
uobnet_crt=$(mktemp --suffix=.crt) || { echo "Failed to create temp file" ; exit 1; }

# Function for cleanup tasks when script exits in any way
cleanup() {
	# Remove temporary files
	rm -f ${uobnet_out} ${uobnet_err} ${uobnet_crt} >/dev/null 2>&1
	# Enable console echo (VPN client disables it for password prompt)
	stty echo
}

# Register cleanup handler
trap cleanup INT TERM EXIT

# Parse options
while getopts "c:C:hu:p:" arg; do
	case ${arg} in
		c)
			if [ -n ${ssl_arg} ]; then
				echo "Cannot define CA directory and file."
				exit 2
			fi
			ssl_arg="-CAfile ${OPTARG}"
			;;
		C)
			if [ -n ${ssl_arg} ]; then
				echo "Cannot define CA directory and file."
				exit 2
			fi
			ssl_arg="-CApath ${OPTARG}"
			;;
		h)
			echo "Usage: ${0} [-c <CA file>] [-C <CA directory>] [-h] [-u <username>] [-p <password>]"
			exit 1
			;;
		u)
			vpn_user="${OPTARG}"
			;;
		p)
			# -p included here so if it's not provided the VPN client will prompt
			vpn_pass="-p ${OPTARG}"
			;;
	esac
done

# Network Connect client segfaults if /etc/resolv.conf doesn't exist
if [ ! -f "/etc/resolv.conf" ]; then
	echo "/etc/resolv.conf does not exist. Please check your hosts configuration."
	exit 6
fi

# If no username was provided prompt for one.
if [ -z ${vpn_user} ]; then
	echo -n "Username: "
	read vpn_user
fi

# If no CA file or directory was provided guess based on distribution name.
if [ -z ${ssl_arg} ]; then
	case $(lsb_release -i | cut -f2) in
		Fedora|CentOS|Scientific|RedHatEnterprise*)
			ca_arg="-CAfile /etc/ssl/certs/ca-bundle.crt"
			;;
		*)
			ca_arg="-CApath /etc/ssl/certs"
			;;
	esac
fi

# Get the certificate from the VPN service. Exit on failure.
if ! openssl s_client -connect ${vpn_host}:${vpn_port} ${ca_arg} </dev/null 1>${uobnet_out} 2>${uobnet_err}; then
	echo "Cannot retrieve certificate."
	exit 3
fi

# Check there were no verification issues. Exit on failure.
if grep "verify return:[^1]" ${uobnet_err} >/dev/null 2>&1; then
	echo "Cannot verify certificate."
	exit 4
fi

# Convert certificate to der format for the VPN client. Exit on failure.
if ! openssl x509 -in ${uobnet_out} -outform der -out ${uobnet_crt} >/dev/null 2>&1; then
	echo "Cannot convert certificate."
	exit 5
fi

# Start the VPN client.
/usr/local/nc/ncsvc -h ${vpn_host} -f ${uobnet_crt} -r ${vpn_realm} -u ${vpn_user}
