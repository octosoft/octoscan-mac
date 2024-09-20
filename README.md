# [OctoSAM Inventory](https://octosoft.ch) Scanner for macOS

## octoscan-mac

### Basic operation

The macOS scanner for OctoSAM Inventory is a bash/zsh shell script that generates a zip archive with the filename extension .scam.

Shell scripting is used to minimize dependencies on the operating system level. Only the shell script is needed to scan a system.
Previous versions of the scanner were implemented using Python, but in macOS 12.3 Apple decided to remove Python from the standard operating system.

The scanner depends mainly on the standard macOS system_profiler utility.
A couple of other tools are also used to provide further information.

### Invocation and collection of generated Files

Typically the scanner is invoked using existing management infrastructure.
It's highly recommended to start the scanner in the user's context (for example as a Launch Agent etc.) as that gives you valuable device affinity information.

### Standalone invocation

Copy the shell script octoscan.py on a USB stick. On the target Mac, open Terminal and navigate to the mounted stick and call the scanner.

```sh
$ cd /Volumes/MYSTICK
./octoscan.sh
```

a .scam File will be created in the current directory. Manually copy the file to the OctoSAM import folder.

### Network integration and automation


```sh
FILE=$(./octoscan.sh -o /tmp)
```

The program emits the generated filename to stdout, use the variable `${FILE}`to further process the file.
It's up to you to transfer the generated files to the OctoSAM Import Service import folder. Choose the method best suited to your environment. Whenever possible use existing infrastructure to copy the files.

### Using an OctoSAM upload server

In Mac environments, copying the scan files to a central Windows share can be a challenge. It's recommended to 
use the OctoSAM provided upload server instead. The upload server provide a facility to upload the generated files over http(s).

Octosoft provides upload servers for Windows/IIS and Linux/nginx

Use the curl utility (or any other tool that supports http(s) file uploads) to upload the generated file.

```sh
FILE="$(./octoscan.sh -o /tmp)"
if curl -F "upload=@${FILE}" https://youruploadserver.yourdomain:/upload/
then
    rm "${FILE}"
fi
```

### Optional Notarized Apple Package

Depending on your system architecture and Mac management philosophy, it's sometimes easier to use a standard package to install and configure the scanner on your Macs.

Octosoft can provide you with a signed and notarized macOS package that installs the scanner with a site-specific configuration.
The package installs the scanner as a LaunchAgent to be started in the user context. 
It provides error checking and automatic upload of the generated files to an OctoSAM upload server. 
The package will be generated on-demand with your site-specific configuration, so all you need to do is to install a .pkg file.

