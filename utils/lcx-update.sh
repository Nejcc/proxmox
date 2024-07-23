#!/usr/bin/env bash

function header_info {
  clear
  cat <<"EOF"
------------------------------------------------------------------------------
                       Nejc/Proxmox LXC Install
------------------------------------------------------------------------------
EOF
}

set -eEuo pipefail

# Define colors
YW="\033[33m"
BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
CL="\033[m"

# Display header
header_info

# Initial prompt
echo "Loading..."
whiptail --backtitle "Proxmox VE Helper Scripts" --title "Proxmox VE LXC Updater" --yesno "This Will Update LXC Containers. Proceed?" 10 58 || exit

# Gather hostname and initialize variables
NODE=$(hostname)
EXCLUDE_MENU=()
MSG_MAX_LENGTH=0

# Prepare menu for excluded containers
while read -r TAG ITEM; do
  OFFSET=2
  (( ${#ITEM} + OFFSET > MSG_MAX_LENGTH )) && MSG_MAX_LENGTH=${#ITEM} + OFFSET
  EXCLUDE_MENU+=("$TAG" "$ITEM " "OFF")
done < <(pct list | awk 'NR>1')

# Get excluded containers from user
excluded_containers=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Containers on $NODE" --checklist "\nSelect containers to skip from updates:\n" 16 $((MSG_MAX_LENGTH + 23)) 6 "${EXCLUDE_MENU[@]}" 3>&1 1>&2 2>&3 | tr -d '"') || exit

# Function to check if a container needs reboot
needs_reboot() {
  local container=$1
  local os=$(pct config "$container" | awk '/^ostype/ {print $2}')
  local reboot_required_file="/var/run/reboot-required.pkgs"
  [[ "$os" == "ubuntu" || "$os" == "debian" ]] && pct exec "$container" -- test -s "$reboot_required_file"
}

# Function to update a container
update_container() {
  local container=$1
  header_info
  local name=$(pct exec "$container" hostname)
  local os=$(pct config "$container" | awk '/^ostype/ {print $2}')
  local disk_info=""
  if [[ "$os" == "ubuntu" || "$os" == "debian" || "$os" == "fedora" ]]; then
    disk_info=$(pct exec "$container" df /boot | awk 'NR==2{gsub("%","",$5); printf "%s %.1fG %.1fG %.1fG", $5, $3/1024/1024, $2/1024/1024, $4/1024/1024 }')
  fi
  echo -e "${BL}[Info]${GN} Updating ${BL}$container${CL} : ${GN}$name${CL} - ${YW}Boot Disk: ${disk_info}%${CL}\n"

  case "$os" in
    alpine) pct exec "$container" -- ash -c "apk update && apk upgrade" ;;
    archlinux) pct exec "$container" -- bash -c "pacman -Syyu --noconfirm" ;;
    fedora | rocky | centos | alma) pct exec "$container" -- bash -c "dnf -y update && dnf -y upgrade" ;;
    ubuntu | debian | devuan) pct exec "$container" -- bash -c "apt-get update && apt-get -yq dist-upgrade && rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED" ;;
  esac
}

# Main script execution
containers_needing_reboot=()
header_info
for container in $(pct list | awk 'NR>1 {print $1}'); do
  if [[ " ${excluded_containers[@]} " =~ " $container " ]]; then
    echo -e "${BL}[Info]${GN} Skipping ${BL}$container${CL}"
    sleep 1
  else
    status=$(pct status $container)
    if [[ "$(pct config $container | grep -q "template:" && echo "true" || echo "false")" == "false" ]] && [[ "$status" == "status: stopped" ]]; then
      echo -e "${BL}[Info]${GN} Starting${BL} $container ${CL}\n"
      pct start $container
      echo -e "${BL}[Info]${GN} Waiting For${BL} $container${CL}${GN} To Start ${CL}\n"
      sleep 5
      update_container $container
      echo -e "${BL}[Info]${GN} Shutting down${BL} $container ${CL}\n"
      pct shutdown $container &
    elif [[ "$status" == "status: running" ]]; then
      update_container $container
    fi
    if needs_reboot "$container"; then
      containers_needing_reboot+=("$container ($name)")
    fi
  fi
done

# Wait for background processes
wait

# Final output
header_info
echo -e "${GN}The process is complete, and the selected containers have been updated.${CL}\n"
if [[ ${#containers_needing_reboot[@]} -gt 0 ]]; then
  echo -e "${RD}The following containers require a reboot:${CL}"
  for container in "${containers_needing_reboot[@]}"; do
    echo "$container"
  done
fi
echo ""
