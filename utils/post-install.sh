#!/usr/bin/env bash

header_info() {
  clear
  cat <<"EOF"
------------------------------------------------------------------------------
                       Nejc/Proxmox Post Install
------------------------------------------------------------------------------
EOF
}

# Color definitions
RD="\033[01;31m"
YW="\033[33m"
GN="\033[1;92m"
CL="\033[m"
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

set -euo pipefail
shopt -s inherit_errexit nullglob

# Message functions
msg_info() { echo -ne " ${HOLD} ${YW}$1..."; }
msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; }

# Function to start the routines
start_routines() {
  header_info

  update_sources
  disable_pve_enterprise
  enable_pve_no_subscription
  correct_ceph_sources
  add_pvetest_repo
  disable_subscription_nag
  configure_high_availability
  update_proxmox_ve
  prompt_reboot
}

# Function to update Proxmox VE sources
update_sources() {
  local choice
  choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SOURCES" \
    --menu "The package manager will use the correct sources to update and install packages on your Proxmox VE server.\n \nCorrect Proxmox VE sources?" 14 58 2 \
    "yes" " " "no" " " 3>&2 2>&1 1>&3)

  if [[ $choice == "yes" ]]; then
    msg_info "Correcting Proxmox VE Sources"
    cat <<EOF >/etc/apt/sources.list
deb http://deb.debian.org/debian bookworm main contrib
deb http://deb.debian.org/debian bookworm-updates main contrib
deb http://security.debian.org/debian-security bookworm-security main contrib
EOF
    echo 'APT::Get::Update::SourceListWarnings::NonFreeFirmware "false";' >/etc/apt/apt.conf.d/no-bookworm-firmware.conf
    msg_ok "Corrected Proxmox VE Sources"
  else
    msg_error "Selected no to Correcting Proxmox VE Sources"
  fi
}

# Function to disable pve-enterprise repository
disable_pve_enterprise() {
  local choice
  choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "PVE-ENTERPRISE" \
    --menu "The 'pve-enterprise' repository is only available to users who have purchased a Proxmox VE subscription.\n \nDisable 'pve-enterprise' repository?" 14 58 2 \
    "yes" " " "no" " " 3>&2 2>&1 1>&3)

  if [[ $choice == "yes" ]]; then
    msg_info "Disabling 'pve-enterprise' repository"
    echo "# deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise" >/etc/apt/sources.list.d/pve-enterprise.list
    msg_ok "Disabled 'pve-enterprise' repository"
  else
    msg_error "Selected no to Disabling 'pve-enterprise' repository"
  fi
}

# Function to enable pve-no-subscription repository
enable_pve_no_subscription() {
  local choice
  choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "PVE-NO-SUBSCRIPTION" \
    --menu "The 'pve-no-subscription' repository provides access to all of the open-source components of Proxmox VE.\n \nEnable 'pve-no-subscription' repository?" 14 58 2 \
    "yes" " " "no" " " 3>&2 2>&1 1>&3)

  if [[ $choice == "yes" ]]; then
    msg_info "Enabling 'pve-no-subscription' repository"
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" >/etc/apt/sources.list.d/pve-install-repo.list
    msg_ok "Enabled 'pve-no-subscription' repository"
  else
    msg_error "Selected no to Enabling 'pve-no-subscription' repository"
  fi
}

# Function to correct Ceph package sources
correct_ceph_sources() {
  local choice
  choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CEPH PACKAGE REPOSITORIES" \
    --menu "The 'Ceph Package Repositories' provides access to both the 'no-subscription' and 'enterprise' repositories (initially disabled).\n \nCorrect 'ceph package sources?" 14 58 2 \
    "yes" " " "no" " " 3>&2 2>&1 1>&3)

  if [[ $choice == "yes" ]]; then
    msg_info "Correcting 'ceph package repositories'"
    cat <<EOF >/etc/apt/sources.list.d/ceph.list
# deb https://enterprise.proxmox.com/debian/ceph-quincy bookworm enterprise
# deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription
# deb https://enterprise.proxmox.com/debian/ceph-reef bookworm enterprise
# deb http://download.proxmox.com/debian/ceph-reef bookworm no-subscription
EOF
    msg_ok "Corrected 'ceph package repositories'"
  else
    msg_error "Selected no to Correcting 'ceph package repositories'"
  fi
}

# Function to add (disabled) pvetest repository
add_pvetest_repo() {
  local choice
  choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "PVETEST" \
    --menu "The 'pvetest' repository can give advanced users access to new features and updates before they are officially released.\n \nAdd (Disabled) 'pvetest' repository?" 14 58 2 \
    "yes" " " "no" " " 3>&2 2>&1 1>&3)

  if [[ $choice == "yes" ]]; then
    msg_info "Adding 'pvetest' repository and set disabled"
    echo "# deb http://download.proxmox.com/debian/pve bookworm pvetest" >/etc/apt/sources.list.d/pvetest-for-beta.list
    msg_ok "Added 'pvetest' repository"
  else
    msg_error "Selected no to Adding 'pvetest' repository"
  fi
}

# Function to disable subscription nag
disable_subscription_nag() {
  if [[ ! -f /etc/apt/apt.conf.d/no-nag-script ]]; then
    local choice
    choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SUBSCRIPTION NAG" \
      --menu "This will disable the nag message reminding you to purchase a subscription every time you log in to the web interface.\n \nDisable subscription nag?" 14 58 2 \
      "yes" " " "no" " " 3>&2 2>&1 1>&3)

    if [[ $choice == "yes" ]]; then
      whiptail --backtitle "Proxmox VE Helper Scripts" --msgbox --title "Support Subscriptions" "Supporting the software's development team is essential. Check their official website's Support Subscriptions for pricing. Without their dedicated work, we wouldn't have this exceptional software." 10 58
      msg_info "Disabling subscription nag"
      echo "DPkg::Post-Invoke { \"dpkg -V proxmox-widget-toolkit | grep -q '/proxmoxlib\.js$'; if [ \$? -eq 1 ]; then { echo 'Removing subscription nag from UI...'; sed -i '/.*data\.status.*{/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; }; fi\"; };" >/etc/apt/apt.conf.d/no-nag-script
      apt --reinstall install proxmox-widget-toolkit &>/dev/null
      msg_ok "Disabled subscription nag (Delete browser cache)"
    else
      whiptail --backtitle "Proxmox VE Helper Scripts" --msgbox --title "Support Subscriptions" "Supporting the software's development team is essential. Check their official website's Support Subscriptions for pricing. Without their dedicated work, we wouldn't have this exceptional software." 10 58
      msg_error "Selected no to Disabling subscription nag"
    fi
  fi
}

# Function to configure high availability
configure_high_availability() {
  if ! systemctl is-active --quiet pve-ha-lrm; then
    local choice
    choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "HIGH AVAILABILITY" \
      --menu "Enable high availability?" 10 58 2 "yes" " " "no" " " 3>&2 2>&1 1>&3)

    if [[ $choice == "yes" ]]; then
      msg_info "Enabling high availability"
      systemctl enable -q --now pve-ha-lrm
      systemctl enable -q --now pve-ha-crm
      systemctl enable -q --now corosync
      msg_ok "Enabled high availability"
    else
      msg_error "Selected no to Enabling high availability"
    fi
  elif systemctl is-active --quiet pve-ha-lrm; then
    local choice
    choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "HIGH AVAILABILITY" \
      --menu "If you plan to utilize a single node instead of a clustered environment, you can disable unnecessary high availability (HA) services, thus reclaiming system resources.\n\nIf HA becomes necessary at a later stage, the services can be re-enabled.\n\nDisable high availability?" 18 58 2 \
      "yes" " " "no" " " 3>&2 2>&1 1>&3)

    if [[ $choice == "yes" ]]; then
      msg_info "Disabling high availability"
      systemctl disable -q --now pve-ha-lrm
      systemctl disable -q --now pve-ha-crm
      systemctl disable -q --now corosync
      msg_ok "Disabled high availability"
    else
      msg_error "Selected no to Disabling high availability"
    fi
  fi
}

# Function to update Proxmox VE
update_proxmox_ve() {
  local choice
  choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "UPDATE" \
    --menu "\nUpdate Proxmox VE now?" 11 58 2 "yes" " " "no" " " 3>&2 2>&1 1>&3)

  if [[ $choice == "yes" ]]; then
    msg_info "Updating Proxmox VE (Patience)"
    apt-get update &>/dev/null
    apt-get -y dist-upgrade &>/dev/null
    msg_ok "Updated Proxmox VE"
  else
    msg_error "Selected no to Updating Proxmox VE"
  fi
}

# Function to prompt for reboot
prompt_reboot() {
  local choice
  choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "REBOOT" \
    --menu "\nReboot Proxmox VE now? (recommended)" 11 58 2 "yes" " " "no" " " 3>&2 2>&1 1>&3)

  if [[ $choice == "yes" ]]; then
    msg_info "Rebooting Proxmox VE"
    sleep 2
    msg_ok "Completed Post Install Routines"
    reboot
  else
    msg_error "Selected no to Rebooting Proxmox VE (Reboot recommended)"
    msg_ok "Completed Post Install Routines"
  fi
}

# Initial header and prompt
header_info
echo -e "\nThis script will Perform Post Install Routines.\n"
while true; do
  read -p "Start the Proxmox VE Post Install Script (y/n)? " yn
  case $yn in
    [Yy]*) break ;;
    [Nn]*) clear; exit ;;
    *) echo "Please answer yes or no." ;;
  esac
done

# Check Proxmox VE version compatibility
if ! pveversion | grep -Eq "pve-manager/8.[0-2]"; then
  msg_error "This version of Proxmox Virtual Environment is not supported"
  echo -e "Requires Proxmox Virtual Environment Version 8.0 or later."
  echo -e "Exiting..."
  sleep 2
  exit
fi

# Start routines
start_routines
