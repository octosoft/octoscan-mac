#!/usr/bin/env bash
#
# OctoSAM Inventory scanner for macOS
#
# (c) 2020 Octosoft AG, CH-6312 Steinhausen, Switzerland
# this code is licensed under the MIT licence
#
# in macos 12.3 Apple chose to remove python from the standard OS delivery
# this is a bash/zsh only version of the scanner
#
# importing of ActiveDirectory or SMBIOS information requires OctoSAM Server 1.10.2.42 or newer
#

build="1.10.2 2022-02-02"

set -euo pipefail

# running on zsh?
if [[ "${ZSH_VERSION:-none}" != "none" ]]; then
	set +o nomatch
	shell_version="zsh ${ZSH_VERSION:-none}"
else
	shell_version="bash ${BASH_VERSION:-none}"
fi

#
# setup working directory where we create the archive
# the bash variant copies/writes the files into a working directory and then zips them into an archive
#

otempdir="$(mktemp -d)"

function f_on_exit() {
	if [ -d "${otempdir}" ]; then
		rm -rf "${otempdir}"
	fi
}

trap "f_on_exit" EXIT

#
# setup some basic information
# it's assumed that these tools just work ....
#

uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
timestamp="$(date '+%Y-%m-%dT%H:%M:%S')"
system="$(uname -s | tr '[:upper:]' '[:lower:]')"
platform="$(uname -v)"
user_id="$(id -u)"
login="$(id -un)"
fqdn="$(hostname -f)"
kerberos="false"

#
# check that we are on macOS
#

case ${system} in

darwin) ;;

*)
	echo "${system} not supported"
	exit 2
	;;
esac

#
# option handling
#

outdir="$(pwd)"

while getopts "o:" opt; do
	case $opt in
	o)
		outdir=$OPTARG
		;;
	*)
		echo "Usage: octoscan.sh [-o output-directory]" >&2
		exit 2
		;;
	esac
done

outfile="${outdir}/${uuid}.scam"

#
# scan!
#

basedir="${otempdir}/${uuid}"

mkdir "${basedir}"

# redirect stderr / stdout into the zip archive for debugging
{

	/usr/sbin/sysctl -a >"${basedir}/sysctl.properties"

	# fallback for system uuid
	/usr/sbin/ioreg -a -rd1 -c IOPlatformExpertDevice >"${basedir}/IOPlatformExpertDevice.xml"

	/usr/sbin/system_profiler -xml SPApplicationsDataType SPSoftwareDataType SPMemoryDataType SPHardwareDataType SPDiagnosticsDataType SPDisplaysDataType SPDiscBurningDataType SPEthernetDataType SPPrintersDataType SPNetworkDataType SPSerialATADataType >"$basedir/system_profiler.xml"

	# scan apps

	cnt=1
	mkdir -p "${basedir}/apps"

	for f in /Applications/*/Contents/Info.plist; do
		if [[ -r "$f" ]]; then
			cp "$f" "${basedir}/apps/app_${cnt}.plist"
			cnt=$((cnt + 1))
		fi
	done

	# scan java

	cnt=1
	mkdir -p "${basedir}/java"

	for f in /Library/Java/JavaVirtualMachines/*/Contents/Info.plist; do
		if [[ -r "$f" ]]; then
			cp "$f" "${basedir}/java/java_${cnt}.plist"
			cnt=$((cnt + 1))
		fi
	done

	# get homebrew inventory if available

	if which brew >/dev/null; then

		mkdir -p "${basedir}/cmd"
		brew info --json=v1 --installed >"${basedir}/cmd/brew.json"
	fi

	# system configuration / active directory
	mkdir -p "${basedir}/scutil"

	/usr/sbin/scutil >"${basedir}/scutil/com_apple_smb" <<EOF
show com.apple.smb
EOF

	/usr/sbin/scutil >"${basedir}/scutil/state_network_netbios" <<EOF
show State:/Network/NetBIOS
EOF

	/usr/sbin/scutil >"${basedir}/scutil/com_apple_opendirectoryd_activedirectory" <<EOF
show com.apple.opendirectoryd.ActiveDirectory
EOF

	# simplistic test if Kerberos is enabled
	if [[ $(/usr/bin/dscl . read "/Users/${login}" AuthenticationAuthority | grep --count "Kerberosv5") -gt 0 ]]; then
	
		kerberos="true"
	fi

}  >"${basedir}/stdout.log" 2>"${basedir}/stderr.log"


cat >"${basedir}/octoscan.xml" <<EOF
<?xml version="1.0" encoding="utf-8" ?>
<octoscan uuid="${uuid}" fqdn="${fqdn}" build="${build}" python="none" shell="${shell_version}" timestamp="${timestamp}" platform="${platform}" >
    <user>
        <info name="login"    type="S"  value="${login}" />
        <info name="user_id"  type="I"  value="${user_id}" />
        <info name="kerberos" type="B"  value="${kerberos}" />
    </user>
</octoscan>
EOF

# zip in a subshell to retain the current directory
(
	cd "${otempdir}"
	zip -rq "${outfile}" "${uuid}"
)

echo "${outfile}"
