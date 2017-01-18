#!/bin/sh

# Vendor and device ID (get with lspci -nn)
vendor_id="10de"
device_id="1b80"
device_id_2="10f0" # HDMI audio controller

# KVM variables
kvm_path="/disk0-disk1-raid1/kvm-nvidia-docker"
kvm_disk_size="50G"
kvm_mem_size="16384"
kvm_cpu_count="16"
kvm_vnc_port="0" # Will be port + 5900
# See /etc/default/keyboard to match your own system
kvm_debian_keyboard_layout="ch"
kvm_debian_keyboard_variant="fr"
kvm_root_password="root"
kvm_hostname="kvm-nvidia-docker"
kvm_ssh_port="2222"

nvidia_docker_url="https://github.com/NVIDIA/nvidia-docker/releases/download/v1.0.0-rc.3/nvidia-docker_1.0.0.rc.3-1_amd64.deb"

# Sanity checks
if ! `grep -q intel_iommu=on /proc/cmdline`; then
  echo 'Kernel must be started with intel_iommu=on'
  echo "Please add the option to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub"
  echo "Then run update-grub and reboot"
  exit 1
fi
if [ -z "`which virt-builder`" ]; then
  echo "Please install virt-builder to create KVM disk image"
  echo "apt-get install --yes libguestfs-tools"
  exit 2
fi
if [ -z "`which qemu-img`" -o -z "`which qemu-system-x86_64`" ]; then
  echo "Please install KVM and its utilities"
  echo "apt-get install --yes qemu-utils qemu-system-x86_64"
  exit 2
fi


# Extract bus ID
bus_ids=`lspci -nn | grep "\[${vendor_id}:${device_id}\]" | cut -f1 -d' ' | sed 's! !!g' | tr "\n" " "`
test -n "${device_id_2}" && bus_ids_2=`lspci -nn | grep "\[${vendor_id}:${device_id_2}\]" | cut -f1 -d' ' | sed 's! !!g' | tr "\n" " "`

# Unload module, should not be necessary
#for module in nvidia_uvm nvidia_modeset nvidia_drm nouveau nvidia; do
#  grep -q "^${module}[[:space:]]" /proc/modules && rmmod ${module}
#done

# Passthough driver
modprobe vfio
modprobe vfio_pci

# Unbind from driver (loop if there's multiple cards with same ids)
for bus_id in ${bus_ids}; do
  test -f "/sys/bus/pci/devices/0000:${bus_id}/driver/unbind" && \
    echo "0000:${bus_id}" > "/sys/bus/pci/devices/0000:${bus_id}/driver/unbind"
done
for bus_id_2 in ${bus_ids_2}; do
  test -f "/sys/bus/pci/devices/0000:${bus_id_2}/driver/unbind" && \
    echo "0000:${bus_id_2}" > "/sys/bus/pci/devices/0000:${bus_id_2}/driver/unbind"
done

# Bind to passthrough driver
echo "${vendor_id} ${device_id}" > /sys/bus/pci/drivers/vfio-pci/new_id
test -n "${device_id_2}" && echo "${vendor_id} ${device_id_2}" > /sys/bus/pci/drivers/vfio-pci/new_id


# Download nvidia-docker deb
rm -f "/tmp/nvidia-docker.deb"
wget "${nvidia_docker_url}" -O "/tmp/nvidia-docker.deb"

# Create KVM disk image
mkdir -p "${kvm_path}"
# Workaround https://github.com/NVIDIA/nvidia-docker/issues/242 by copying skeleton init script
# Should be removed when the bug will be fixed
virt-builder debian-8 --arch amd64 --format qcow2 -o "${kvm_path}/disk0.img"  \
  --size "${kvm_disk_size}" \
  --root-password password:"${kvm_root_password}" \
  --hostname "${kvm_hostname}" \
  --upload "/tmp/nvidia-docker.deb":/root \
  --install apt-transport-https,linux-headers-amd64 \
  --write /etc/apt/sources.list:"# See sources.list.d" \
  --write /etc/apt/sources.list.d/docker.list:"deb [trusted=yes] https://apt.dockerproject.org/repo debian-jessie main" \
  --write /etc/apt/sources.list.d/debian.list:"deb http://ftp.fr.debian.org/debian jessie main contrib non-free" \
  --write /etc/apt/sources.list.d/debian-backports.list:"deb http://ftp.fr.debian.org/debian jessie-backports main contrib non-free" \
  --run-command 'apt-get update' \
  --install docker-engine \
  --run-command 'cp /etc/init.d/skeleton /etc/init.d/nvidia-docker' \
  --run-command 'dpkg-reconfigure -fnoninteractive openssh-server' \
  --run-command "sed -i 's!PermitRootLogin without-password!PermitRootLogin yes!' /etc/ssh/sshd_config" \
  --run-command 'dpkg -i /root/nvidia-docker.deb' \
  --run-command "sed -i 's|XKBLAYOUT=.*|XKBLAYOUT=\"${kvm_debian_keyboard_layout}\"|' /etc/default/keyboard" \
  --run-command "sed -i 's|XKBVARIANT=.*|XKBVARIANT=\"${kvm_debian_keyboard_variant}\"|' /etc/default/keyboard" \
  --run-command 'apt-get install --yes -t jessie-backports nvidia-smi nvidia-kernel-dkms nvidia-cuda-mps nvidia-driver-bin nvidia-persistenced libcuda1'


# Create a start script
cat << EOF > "${kvm_path}/start.sh"

qemu-system-x86_64 \\
  -enable-kvm -m ${kvm_mem_size} -smp ${kvm_cpu_count} \\
  -cpu host,kvm=off \\
  -device vfio-pci,host=${bus_id} \\
  -drive file="${kvm_path}/disk0.img" \\
  -vnc 0.0.0.0:${kvm_vnc_port} \\
  -net nic,model=virtio \\
  -net user,hostfwd=tcp::${kvm_ssh_port}-:22
EOF

chmod 0755 "${kvm_path}/start.sh"

echo
echo
echo "You can start the KVM by running ${kvm_path}/start.sh"
echo "And get the VNC console on `hostname -f`:`expr ${kvm_vnc_port} + 5900`"
echo "Or SSH on ssh root@`hostname -f` -p${kvm_ssh_port}"
