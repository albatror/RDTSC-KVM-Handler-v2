#!/bin/bash
# Patch rdtsc for Linux kernel 6.11.0-26-generic

read -p "Make sure to enable Ubuntu Software -> Source code in Software & Updates first! Then press enter to continue..."
sudo apt update
sudo apt install dpkg-dev -y

read -p "Delete pre-existing kernels with -rdtsc in the name? [y/n] " DELETEOLDKERNELS
if [ "$DELETEOLDKERNELS" = "y" ]; then
  echo "Removing existing kernels that contain -rdtsc in the name..."
  sudo shred -u /boot/*-rdtsc
fi

echo "Removing any folders matching ./linux-*6.11.0*"
sudo rm -rf ./linux-*6.11.0*
echo "Downloading source: linux-image-unsigned-6.11.0-26-generic..."
sudo apt source linux-image-unsigned-6.11.0-26-generic
echo "Changing permissions on downloaded source directory..."
sudo chown -R $USER:$USER linux-*6.11.0*
sudo chmod -R 777 linux-*6.11.0*
cd ./linux-*6.11.0*
patch -p1 < ../kernel-patch-6.11.0-26.patch

read -p "Would you like to apply the ACS override patch for PCI devices ? [y/n] " APPLYACS
if [ "$APPLYACS" = "y" ]; then
  patch -p1 < ../acso-6.11.0-26.patch
fi

# Get core count - 2 for faster make, e.g. if you have 8 cores, 6 will
# be used by make
CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || sysctl -n hw.ncpu)
CORES=$(($CORES - 2))

# Fix for error: ISO C90 forbids mixed declarations and code
sed -i 's/KBUILD_CFLAGS += -Wdeclaration-after-statement/#KBUILD_CFLAGS += -Wdeclaration-after-statement/' Makefile

# Fix the kernel version
sed -i 's/SUBLEVEL = .*/SUBLEVEL = 0/' Makefile
sed -i 's/EXTRAVERSION =.*/EXTRAVERSION = -26/' Makefile

# Build and install the kernel
sudo apt install git libncurses-dev gawk flex bison openssl libssl-dev dkms libelf-dev autoconf llvm build-essential -y
cp ../.config .
make -j$CORES bzImage
make -j$CORES modules
echo "Installing kernel modules..."
sudo make modules_install -j$CORES
echo "Installing kernel headers..."
sudo make headers_install -j$CORES
echo "Installing kernel..."
sudo make install
echo "Generating initrd.img..."
sudo update-initramfs -c -k 6.11.0-26-rdtsc
echo "Updating GRUB bootloader..."
sudo grub-mkconfig -o /boot/grub/grub.cfg
echo "Cleaning up..."
sudo rm -rf ./linux-*

read -p "Make the Grub bootloader menu visible? [y/n] " GRUBVISIBLE
if [ "$GRUBVISIBLE" = "y" ]; then
  sudo sed -i 's/GRUB_TIMEOUT_STYLE=hidden/#GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
  sudo sed -i 's/GRUB_TIMEOUT=0/GRUB_TIMEOUT=-1/' /etc/default/grub
  sudo update-grub
else
  echo 'Boot into Grub bootloader menu by holding Shift (BIOS) or Esc (UEFI).'
fi

if [ "$APPLYACS" = "y" ]; then
  if grep -R "pcie_acs_override" "/etc/default/grub"
    then
      echo "Boot parameter pcie_acs_override already in /etc/default/grub... skipping"
    else
      echo "Make sure to edit /etc/default/grub and add the following to your boot options: "
      echo "intel_iommu=on pcie_acs_override=downstream"
  fi
fi

echo 'All finished. In the Grub menu, go to [Advanced Options for Ubuntu] and select 6.11.0-26-rdtsc.'
