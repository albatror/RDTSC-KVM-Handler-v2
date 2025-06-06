#!/bin/bash
set -euo pipefail

KVER="6.11"
KVERSUF="6.11-rdtsc"
PATCH_DIR="$(pwd)"
CORES=$(( $(nproc) - 1 ))

read -rp "Supprimer les anciens noyaux -rdtsc ? [y/n] " DELETE
if [[ "${DELETE,,}" == "y" ]]; then
  sudo rm -f /boot/*-rdtsc*
fi

echo "📥 Téléchargement du kernel Linux ${KVER} (branch 6.11.x)"
wget -c https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KVER}.tar.xz
tar -xf linux-${KVER}.tar.xz
cd linux-${KVER}

echo "🔧 Application du patch RDTSC…"
patch -p1 < "${PATCH_DIR}/kernel-patch-6.11.0-26.patch"

read -rp "Appliquer le patch ACS override ? [y/n] " ACS
if [[ "${ACS,,}" == "y" ]]; then
  patch -p1 < "${PATCH_DIR}/acso-6.11.0-26.patch"
fi

echo "📦 Installation des dépendances de build…"
sudo apt update
sudo apt install -y build-essential libncurses-dev bison flex libssl-dev libelf-dev bc

echo "⚙️ Préparation du fichier .config…"
if [[ -f "${PATCH_DIR}/.config" ]]; then
  cp "${PATCH_DIR}/.config" .config
else
  echo "Génération d'une config par défaut…"
  make defconfig
fi

make olddefconfig
make modules_prepare

echo "🏗️ Compilation du bzImage et des modules (${CORES} threads)…"
make -j"$CORES" bzImage
make -j"$CORES" modules

echo "📦 Installation des modules…"
sudo make modules_install

echo "🧩 Installation du noyau…"
sudo make install

echo "📸 Génération de l'initrd…"
sudo update-initramfs -c -k "${KVERSUF}"

echo "🔄 Mise à jour de GRUB…"
sudo update-grub

read -rp "Rendre le menu GRUB visible ? [y/n] " VISIBLE
if [[ "${VISIBLE,,}" == "y" ]]; then
  sudo sed -i 's/GRUB_TIMEOUT_STYLE=hidden/#&/' /etc/default/grub
  sudo sed -i 's/GRUB_TIMEOUT=0/GRUB_TIMEOUT=-1/' /etc/default/grub
  sudo update-grub
fi

if [[ "${ACS,,}" == "y" ]]; then
  if ! grep -q "pcie_acs_override" /etc/default/grub; then
    cat <<EOF
⚠️  Ajoutez dans /etc/default/grub :
  GRUB_CMDLINE_LINUX_DEFAULT="... intel_iommu=on pcie_acs_override=downstream ..."
Puis : sudo update-grub
EOF
  else
    echo "pcie_acs_override déjà présent dans GRUB"
  fi
fi

echo -e "\n✅ TERMINE ! Lors du prochain redémarrage, sélectionne 'Advanced options' → 'Linux ${KVERSUF}' dans GRUB."

