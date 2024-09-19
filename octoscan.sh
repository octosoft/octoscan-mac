#!/usr/bin/env bash
#
# OctoSAM Inventory scanner for macOS
#
# (c) 2024 Octosoft AG, CH-6312 Steinhausen, Switzerland
# this code is licensed under the MIT licence
#
# in macos 12.3 Apple chose to remove python from the standard OS delivery
# this is a bash/zsh only version of the scanner
#

build="1.10.9 2024-09-19"

# for debugging/development only:
# set -euo pipefail

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
tag=""

while getopts "o:" opt; do
	case $opt in
	o)
		outdir=$OPTARG
		;;
	t)
		# for debugging
		tag=$OPTARG
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
	nice -n 20 /usr/sbin/ioreg -a -rd1 -c IOPlatformExpertDevice >"${basedir}/IOPlatformExpertDevice.xml"

	nice -n 20 /usr/sbin/system_profiler -xml SPApplicationsDataType SPSoftwareDataType SPMemoryDataType SPHardwareDataType SPDiagnosticsDataType SPDisplaysDataType SPDiscBurningDataType SPEthernetDataType SPPrintersDataType SPNetworkDataType SPSerialATADataType >"$basedir/system_profiler.xml"

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

	# older javas
	for f in "/Library/Internet Plug-ins"/*/Contents/Info.plist; do
		if [[ -r "$f" ]]; then
			cp "$f" "${basedir}/java/java_${cnt}.plist"
			cnt=$((cnt + 1))
		fi
	done

	# new in 1.10.7 call the java executables and get detailed version information
	# the produced files are in the same format as the Linux scanner 

	mkdir -p "${basedir}/java/static"

	#  remember that read from a pipe starts a subshell which would reset the counter
	#  therefore we use only one find comommnd instead of a loop
	#
	#  we use find pipe to read here to deal with typical mac paths with spaces
	
	cnt=1

	find /Library /Applications -name java -type f -perm +0111 -print | while read -r f; do

		echo "Found: ${f}"
		mkdir -p "${basedir}/java/static/opt_${cnt}"

		# TODO: check usagetracker and other features

		# tivial check if its a JDK or JRE (we assume that JDK has a javac command)
		VARIANT="JRE"

		if [[ -f "${f}c" ]]; then
			VARIANT="JDK"
		fi

		{
			echo "Path:${f}"
			echo "Variant:${VARIANT}"
			echo "Features:"
		} > "${basedir}/java/static/opt_${cnt}/version"

		echo "$basedir/java/static/opt_${cnt}/version"

		if "${f}" -version >>"${basedir}/java/static/opt_${cnt}/version" 2>&1; then
			:
		else
			echo "FAILED: java -version failed for ${f} exit code $?" >>"${basedir}/java/static/opt_${cnt}/version"
		fi

		cnt=$((cnt + 1))

		echo "cnt=$cnt"

	done

	# get the java homes

	mkdir -p "${basedir}/cmd"

	/usr/libexec/java_home -V > "${basedir}/cmd/java_home" 2>&1

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

	# virtualbox extensions

	if [[ -d "/Applications/Virtualbox.app" ]]; then
		mkdir -p "${basedir}/virtualbox"
		if /Applications/Virtualbox.app/Contents/MacOS/VBoxManage list extpacks >"${basedir}/virtualbox/extpacks.txt"; then
			:
		fi
		cnt=1
		mkdir -p "${basedir}/virtualbox"

		for f in /Applications/Virtualbox.app/Contents/MacOS/ExtensionPacks/*/*.xml; do
			if [[ -r "$f" ]]; then
				cp "$f" "${basedir}/virtualbox/extension_${cnt}.xml"
				cnt=$((cnt + 1))
			fi
		done
	fi

} >"${basedir}/stdout.log" 2>"${basedir}/stderr.log"

cat >"${basedir}/octoscan.xml" <<EOF
<?xml version="1.0" encoding="utf-8" ?>
<octoscan uuid="${uuid}" fqdn="${fqdn}" build="${build}" python="none" shell="${shell_version}" timestamp="${timestamp}" platform="${platform}" >
    <config>
		<info name="tag" type="S" value="${tag}" />
	</config>
    <user>
        <info name="login"    type="S"  value="${login}" />
        <info name="user_id"  type="I"  value="${user_id}" />
        <info name="kerberos" type="B"  value="${kerberos}" />
    </user>
</octoscan>
EOF

# zip in a subshell to retain the current directory
(
	cd "${otempdir}" || exit 2
	zip -rq "${outfile}" "${uuid}"
)

echo "${outfile}"
