#!/bin/bash
set -euo pipefail

# Get Ubuntu version and current date
VER=$(lsb_release -rs)
DATE=$(date)

# Function to check supported Ubuntu version
check_version() {
	case $VER in
		"16.04" | "18.04" | "20.04" | "22.04" | "24.01")
			echo "[+] Ubuntu $VER detected"
			;;
		*)
			echo "[!] This Ubuntu version $VER is not supported"
			exit 1
			;;
	esac
}

# Function to update repositories
update_repo() {
	apt update
}

# Function to upgrade installed packages
upgrade_repo() {
	apt upgrade -y
}

# Function to remove unused packages
autoremove_repo() {
	apt autoremove -y
}

# Function to install a service
install_service() {
	apt -yq install "$1"
}

# Check for root privileges, network connectivity, and dependencies
check_dependency() {
	# Check if script is run as root
	if [[ $EUID -ne 0 ]]; then
	   echo "[!] This script must be run as root"
	   exit 1
	fi

	# Check network status (Internet and DNS)
	if ping -q -c 3 -W 1 www.google.com > /dev/null 2>&1; then
		echo "[+] Network connection is OK"
	else
		if ping -q -c 3 -W 1 8.8.8.8 > /dev/null 2>&1; then
			echo "[!] Check your DNS settings"
			exit 1
		else
			echo "[!] Check your NETWORK settings"
			exit 1
		fi
	fi

	# Check if whiptail is installed, otherwise install it
	if ! which whiptail > /dev/null 2>&1; then
		echo "[+] Installing whiptail..."
		install_service whiptail
	else
		echo "[+] whiptail is already installed"
	fi
}

# Function to display ASCII art
display_ascii() {
	echo -e '
		
    ░██████╗███████╗██████╗░██╗░░░██╗███████╗██████╗░░░░░░░██╗███╗░░██╗██╗████████╗
    ██╔════╝██╔════╝██╔══██╗██║░░░██║██╔════╝██╔══██╗░░░░░░██║████╗░██║██║╚══██╔══╝
    ╚█████╗░█████╗░░██████╔╝╚██╗░██╔╝█████╗░░██████╔╝█████╗██║██╔██╗██║██║░░░██║░░░
    ░╚═══██╗██╔══╝░░██╔══██╗░╚████╔╝░██╔══╝░░██╔══██╗╚════╝██║██║╚████║██║░░░██║░░░
    ██████╔╝███████╗██║░░██║░░╚██╔╝░░███████╗██║░░██║░░░░░░██║██║░╚███║██║░░░██║░░░
    ╚═════╝░╚══════╝╚═╝░░╚═╝░░░╚═╝░░░╚══════╝╚═╝░░╚═╝░░░░░░╚═╝╚═╝░░╚══╝╚═╝░░░╚═╝░░░                                              
	'
	sleep 3
}

# Function to disable IPv6
dis_ipv6() {
	case $VER in
		"16.04")
			# Disable IPv6 on Ubuntu 16.04
			echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
			echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
			echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf
			sysctl -p
			;;
		"18.04" | "20.04" | "22.04" | "24.01")
			# Disable IPv6 on Ubuntu 18.04, 20.04, 22.04, and 24.01
			sed -i -e 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="ipv6.disable=1"/' /etc/default/grub
			update-grub
			install_service net-tools  # Install net-tools if needed (for ifconfig, etc.)
			;;
		*)
			echo "[!] Your Ubuntu version $VER is not supported for IPv6 disabling"
			exit 1
			;;
	esac
}

# Function to get confirmation to disable IPv6
get_confirmation_ipv6_disable() {
	if (whiptail --title "IPv6" --yesno "This script will disable IPv6. Do you agree?" 8 78); then
		echo "[+] Disabling IPv6..."
		dis_ipv6
	else
		echo "[!] IPv6 disabling was canceled."
	fi
}

# Function to enable and configure UFW (optional)
# enable_ufw() {
# 	install_service ufw
# 	echo "[+] Configuring UFW..."
# 	ufw allow 22
# 	ufw --force enable
# 	echo "[++] To allow other ports, use: ufw allow [PORT]"
# 	echo "[++] Example to allow port 80: ufw allow 80"
# 	sleep 5
# }

# Function to prompt user to enable UFW (optional)
ufw_support() {
	if (whiptail --title "Firewall" --yesno "Enable firewall (UFW) on this server?" 8 78); then
		echo "[+] Enabling UFW..."
		enable_ufw
	else
		echo "[!] UFW setup was skipped."
	fi	
}

# Function to prompt for date reconfiguration
reconfig_date() {
	if (whiptail --title "Date" --yesno "The current date is $DATE. Is it correct?" 8 78); then
		echo "[+] Date confirmed as correct."
	else
		echo "[+] Reconfiguring date..."
		dpkg-reconfigure tzdata
	fi
}

# Function to reboot the server with a warning
cmd_reboot() {
	whiptail --title "Rebooting..." --msgbox "The server will reboot in 5 seconds." 8 78
	sleep 5
	reboot
}

# Main function to run all tasks
main() {
	# Display ASCII art
	display_ascii

	# Check Ubuntu version
	check_version

	# Check script dependencies
	check_dependency

	# Get confirmation for disabling IPv6
	get_confirmation_ipv6_disable

	# Optionally configure UFW (commented out by default)
	# ufw_support

	# Reconfigure date if needed
	reconfig_date

	# Update and upgrade repositories
	update_repo
	upgrade_repo

	# Clean up unused packages
	autoremove_repo

	# Reboot the server
	cmd_reboot
}

# Call the main function
main
