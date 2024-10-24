#!/usr/bin/env bash
#
##DO NOT RUN DIRECTLY
##Self: bash <(curl -qfsSL "https://raw.githubusercontent.com/Azathothas/flatimage-base/refs/heads/main/archlinux_bootstrap.sh")
#
#-------------------------------------------------------#
set -x
#Sanity Checks
if [ -z "${FIM_SRCDIR}" ] || \
   [ -z "${FIM_BINDIR}" ] || \
   [ -z "${FIM_IMGDIR}" ]; then
 #exit
  echo -e "\n[+] Skipping Builds...\n"
  exit 1
fi
if [ ! -d "${FIM_BINDIR}" ] || [ $(du -s "${FIM_BINDIR}" | cut -f1) -le 1000 ]; then
    echo -e "\n[+] FIM_BINDIR is Empty or Broken\n"
    exit 1
fi
if ! declare -F create_flatimage_base >/dev/null; then
    echo -e "\n[+] create_flatimage_base Function is undefined\n"
    exit 1
fi
set +x
#-------------------------------------------------------#


#-------------------------------------------------------#
##ArchLinux
 echo -e "\n[+] Creating ArchLinux.FlatImage\n"
 #Bootstrap
 pushd "$(mktemp -d)" >/dev/null 2>&1
  #docker stop "archlinux" 2>/dev/null ; docker rm "archlinux" 2>/dev/null
  #docker run --name "archlinux" --privileged "azathothas/archlinux:latest" sh -c "hostname 2>/dev/null; cat "/etc/os-release" 2>/dev/null" && docker export "$(docker ps -aqf 'name=archlinux')" --output "rootfs.tar"
  if [ "$(uname  -m)" == "x86_64" ]; then
    aria2c "https://pub.ajam.dev/utils/archlinux-$(uname -m)/rootfs.tar.zst" \
    --split="16" --max-connection-per-server="16" --min-split-size="1M" \
    --check-certificate="false" --console-log-level="error" --user-agent="${USER_AGENT}" \
    --max-tries="10" --retry-wait="5" --connect-timeout="60" --timeout="600" \
    --download-result="default" --allow-overwrite --out="./ROOTFS.tar.zst" 2>/dev/null
    mkdir -pv "./rootfs" && export ROOTFS_DIR="$(realpath "./rootfs")"
    bsdtar -x -f "./ROOTFS.tar.zst" -C "${ROOTFS_DIR}" --strip-components=1 2>/dev/null
   elif [ "$(uname  -m)" == "aarch64" ]; then
    aria2c "https://pub.ajam.dev/utils/archlinuxarm-$(uname -m)/rootfs.tar.gz" \
    --split="16" --max-connection-per-server="16" --min-split-size="1M" \
    --check-certificate="false" --console-log-level="error" --user-agent="${USER_AGENT}" \
    --max-tries="10" --retry-wait="5" --connect-timeout="60" --timeout="600" \
    --download-result="default" --allow-overwrite --out="./ROOTFS.tar.gz" 2>/dev/null
    mkdir -pv "./rootfs" && export ROOTFS_DIR="$(realpath "./rootfs")"
    bsdtar -x -f "./ROOTFS.tar.gz" -C "${ROOTFS_DIR}" 2>/dev/null
   fi
  if [ -d "${ROOTFS_DIR}" ] && [ $(du -s "${ROOTFS_DIR}" | cut -f1) -gt 10000 ]; then
    if [ -n "${ROOTFS_DIR+x}" ] && [[ "${ROOTFS_DIR}" == "/tmp"* ]]; then
       bsdtar -x -f "./rootfs.tar" -C "${ROOTFS_DIR}" 2>/dev/null
       du -sh "${ROOTFS_DIR}"
       wget "https://bin.ajam.dev/$(uname -m)/rate-mirrors" -O "./rate-mirrors" && chmod +x "./rate-mirrors"
       if [ "$(uname  -m)" == "aarch64" ]; then
         "./rate-mirrors" --allow-root --disable-comments-in-file --save "./mirrors.txt" archarm
       elif [ "$(uname  -m)" == "x86_64" ]; then
         "./rate-mirrors" --allow-root --disable-comments-in-file --save "./mirrors.txt" arch
       fi
       cat "./mirrors.txt" | sudo tee "${ROOTFS_DIR}/etc/pacman.d/mirrorlist"
       sudo rm -rfv "${ROOTFS_DIR}/var/lib/pacman/sync/"*
       sudo rm -rfv "${ROOTFS_DIR}/etc/pacman.d/gnupg/"*
       sudo sed '/DownloadUser/d' -i "${ROOTFS_DIR}/etc/pacman.conf"
       #sudo sed 's/^.*Architecture\s*=.*$/Architecture = auto/' -i "${ROOTFS_DIR}/etc/pacman.conf"
       sudo sed '0,/^.*SigLevel\s*=.*/s//SigLevel = Never/' -i "${ROOTFS_DIR}/etc/pacman.conf"
       #sudo sed 's/^.*SigLevel\s*=.*$/SigLevel = Never/' -i "${ROOTFS_DIR}/etc/pacman.conf"
       sudo sed '/#\[multilib\]/,/#Include = .*/s/^#//' -i "${ROOTFS_DIR}/etc/pacman.conf"
       echo -e "nameserver 8.8.8.8\nnameserver 2620:0:ccc::2" | sudo tee "${ROOTFS_DIR}/etc/resolv.conf"
       echo -e "nameserver 1.1.1.1\nnameserver 2606:4700:4700::1111" | sudo tee -a "${ROOTFS_DIR}/etc/resolv.conf"
       sudo unlink "${ROOTFS_DIR}/var/lib/dbus/machine-id" 2>/dev/null
       sudo unlink "${ROOTFS_DIR}/etc/machine-id" 2>/dev/null
       sudo rm -rvf "${ROOTFS_DIR}/etc/machine-id"
       sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c 'systemd-machine-id-setup --print 2>/dev/null' | sudo tee "${ROOTFS_DIR}/var/lib/dbus/machine-id"
       sudo ln --symbolic --force --relative "${ROOTFS_DIR}/var/lib/dbus/machine-id" "${ROOTFS_DIR}/etc/machine-id"
       sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c 'pacman -Scc --noconfirm'
       sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c 'pacman -Syyu archlinux-keyring pacutils --noconfirm'
       sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c 'pacman-key --init'
       echo "disable-scdaemon" | sudo tee "/etc/pacman.d/gnupg/gpg-agent.conf"
       #timeout 30s sudo chroot "${ROOTFS_DIR}" "/bin/bash" -c 'pacman-key --populate archlinux'
       timeout 30s sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c 'pacman-key --populate archlinux'
       sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c 'pacman -y --sync --refresh --refresh --sysupgrade --noconfirm --debug'
       sudo curl -qfsSL "https://raw.githubusercontent.com/Azathothas/flatimage-base/refs/heads/main/archlinux_hooks.sh" -o "${ROOTFS_DIR}/arch_hooks.sh"
       sudo chmod +x "${ROOTFS_DIR}/arch_hooks.sh"
       sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c '"/arch_hooks.sh"'
       sudo rm -rfv "${ROOTFS_DIR}/arch_hooks.sh"
       echo "LANG=en_US.UTF-8" | sudo tee "${ROOTFS_DIR}/etc/locale.conf"
       echo "LANG=en_US.UTF-8" | sudo tee -a "${ROOTFS_DIR}/etc/locale.conf"
       echo "LANGUAGE=en_US:en" | sudo tee -a "${ROOTFS_DIR}/etc/locale.conf"
       echo "LC_ALL=en_US.UTF-8" | sudo tee -a "${ROOTFS_DIR}/etc/locale.conf"
       echo "en_US.UTF-8 UTF-8" | sudo tee -a "${ROOTFS_DIR}/etc/locale.gen"
       echo "LC_ALL=en_US.UTF-8" | sudo tee -a "${ROOTFS_DIR}/etc/environment"
       sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c 'locale-gen'
       sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c 'locale-gen "en_US.UTF-8"'
       sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c 'pacman -y --sync --refresh --refresh --sysupgrade --noconfirm'
       #packages="alsa-lib alsa-plugins alsa-tools alsa-utils binutils fakeroot fakechroot git intel-media-driver lib32-alsa-lib lib32-mesa lib32-alsa-plugins lib32-libpulse libva-intel-driver lib32-libva-intel-driver lib32-libva-mesa-driver lib32-libvdpau lib32-mesa-utils lib32-nvidia-utils lib32-pipewire lib32-pipewire-jack lib32-sdl2 lib32-vulkan-icd-loader lib32-vulkan-intel lib32-vulkan-mesa-layers lib32-vulkan-radeon lib32-libxkbcommon libpulse libusb libva-mesa-driver libva-utils libvdpau libxkbcommon mesa mesa-utils nvidia-prime nvidia-utils pipewire pipewire-alsa pipewire-jack pipewire-pulse sdl2 vulkan-icd-loader vulkan-intel vulkan-mesa-layers vulkan-radeon vulkan-tools wireplumber"
       #for pkg in $packages; do sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c "pacman -Sy "$pkg" --needed --noconfirm" ; done
       sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c 'pacman -Sy bash binutils curl fakeroot sudo wget --needed --noconfirm'
       sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c 'pacman -Rsn base-devel --noconfirm'
       sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c 'pacman -Rsn perl --noconfirm'
       sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c 'pacman -Rsn python --noconfirm'
       sudo "${FIM_BINDIR}/proot" --kill-on-exit -R "${ROOTFS_DIR}" "/bin/bash" -c 'pacman -Scc --noconfirm'
       sudo rm -rfv "${ROOTFS_DIR}/usr/share/gtk-doc/"* 2>/dev/null
       sudo rm -rfv "${ROOTFS_DIR}/usr/share/man/"* 2>/dev/null
       sudo rm -rfv "${ROOTFS_DIR}/usr/share/help/"* 2>/dev/null
       sudo rm -rfv "${ROOTFS_DIR}/usr/share/info/"* 2>/dev/null
       sudo rm -rfv "${ROOTFS_DIR}/usr/share/doc/"* 2>/dev/null
       sudo rm -rfv "${ROOTFS_DIR}/var/tmp/"* 2>/dev/null
       sudo rm -rfv "${ROOTFS_DIR}/var/lib/pacman/sync/"* 2>/dev/null
       sudo rm -rfv "${ROOTFS_DIR}/var/cache/pacman/pkg/"* 2>/dev/null
       sudo find "${ROOTFS_DIR}/boot" -mindepth 1 -delete 2>/dev/null
       sudo find "${ROOTFS_DIR}/dev" -mindepth 1 -delete 2>/dev/null
       sudo find "${ROOTFS_DIR}/proc" -mindepth 1 -delete 2>/dev/null
       sudo find "${ROOTFS_DIR}/run" -mindepth 1 -delete 2>/dev/null
       sudo find "${ROOTFS_DIR}/sys" -mindepth 1 -delete 2>/dev/null
       sudo find "${ROOTFS_DIR}/tmp" -mindepth 1 -delete 2>/dev/null
       sudo find "${ROOTFS_DIR}/usr/include" -mindepth 1 -delete 2>/dev/null
       sudo find "${ROOTFS_DIR}/usr/lib" -type f -name "*.a" -print -exec sudo rm -rfv {} 2>/dev/null \; 2>/dev/null
       sudo find "${ROOTFS_DIR}/usr/lib32" -type f -name "*.a" -print -exec sudo rm -rfv {} 2>/dev/null \; 2>/dev/null
       sudo find "${ROOTFS_DIR}/etc/pacman.d/gnupg" -type f -name "S.*" -print -exec sudo rm -rfv {} 2>/dev/null \; 2>/dev/null
       sudo find "${ROOTFS_DIR}/usr/share/locale" -mindepth 1 -maxdepth 1 ! -regex '.*/\(locale.alias\|en\|en_US\)$' -exec sudo rm -rfv {} + 2>/dev/null
       sudo find "${ROOTFS_DIR}/usr/share/doc" -mindepth 1 -delete 2>/dev/null
       sudo find "${ROOTFS_DIR}/usr/share/gtk-doc" -mindepth 1 -delete 2>/dev/null
       sudo find "${ROOTFS_DIR}/usr/share/help" -mindepth 1 -delete 2>/dev/null
       sudo find "${ROOTFS_DIR}/usr/share/info" -mindepth 1 -delete 2>/dev/null
       sudo find "${ROOTFS_DIR}/usr/share/man" -mindepth 1 -delete 2>/dev/null
       sudo find "${ROOTFS_DIR}" -type d -name '__pycache__' -exec sudo rm -rfv {} \; 2>/dev/null
       sudo find "${ROOTFS_DIR}" -type f -name '*.pacnew' -exec sudo rm -rfv {} \; 2>/dev/null
       sudo find "${ROOTFS_DIR}" -type f -name '*.pacsave' -exec sudo rm -rfv {} \; 2>/dev/null
       sudo find "${ROOTFS_DIR}/var/log" -type f -name '*.log' -exec sudo rm -rfv {} \; 2>/dev/null
       sudo rm -rfv "${ROOTFS_DIR}/"{tmp,proc,sys,dev,run}
       sudo mkdir -pv "${ROOTFS_DIR}/"{tmp,proc,sys,dev,run/media,mnt,media,home}
       sudo rm -fv "${ROOTFS_DIR}"/etc/{host.conf,hosts,passwd,group,nsswitch.conf}
       sudo touch "${ROOTFS_DIR}"/etc/{host.conf,hosts,passwd,group,nsswitch.conf}
       du -sh "${ROOTFS_DIR}"
    fi
  fi
 #Setup FS
  if [ -d "${ROOTFS_DIR}" ] && [ $(du -s "${ROOTFS_DIR}" | cut -f1) -gt 10000 ]; then
    popd >/dev/null 2>&1 ; pushd "${FIM_SRCDIR}" >/dev/null 2>&1
     rm -rfv "${FIM_TMPDIR}/archlinux" 2>/dev/null
     mkdir -pv "${FIM_TMPDIR}/archlinux/fim/config"
     mkdir -pv "${FIM_TMPDIR}/archlinux/fim/static"
     sudo rsync -achv --mkpath "${ROOTFS_DIR}/." "${FIM_TMPDIR}/archlinux"
     #sudo ln --symbolic --force --verbose "/usr/share" "${FIM_TMPDIR}/archlinux/usr"
     sudo chown -R "$(whoami):$(whoami)" "${FIM_TMPDIR}/archlinux" && chmod -R 755 "${FIM_TMPDIR}/archlinux"
    #Copy Bins 
     rsync -achv --mkpath "${FIM_BINDIR}/." "${FIM_TMPDIR}/archlinux/fim/static"
    #Copy Desktop, Icon & AppStream
     mkdir -pv "${FIM_TMPDIR}/archlinux/fim/desktop"
     cp -fv "${FIM_SRCDIR}/mime/icon.svg" "${FIM_TMPDIR}/archlinux/fim/desktop/icon.svg"
     cp -fv "${FIM_SRCDIR}/mime/flatimage.xml" "${FIM_TMPDIR}/archlinux/fim/desktop/flatimage.xml"
    #Create
     create_flatimage_base archlinux || true
    #Info
     "${FIM_TMPDIR}/archlinux.flatimage" fim-env add 'FIM_DIST=archlinux' 2>/dev/null
     "${FIM_TMPDIR}/archlinux.flatimage" fim-env list 2>/dev/null
     "${FIM_TMPDIR}/archlinux.flatimage" fim-perms add "audio,dbus_user,dbus_system,gpu,home,input,media,network,udev,usb,xorg,wayland"
     "${FIM_TMPDIR}/archlinux.flatimage" fim-perms list
     "${FIM_TMPDIR}/archlinux.flatimage" fim-commit
  fi
  unset ROOTFS_DIR
 #Copy
  if [[ -f "${FIM_TMPDIR}/archlinux.flatimage" ]] && [[ $(stat -c%s "${FIM_TMPDIR}/archlinux.flatimage") -gt 10000 ]]; then
     rsync -achLv "${FIM_TMPDIR}/archlinux.flatimage" "${FIM_IMGDIR}"
     realpath "${FIM_IMGDIR}/archlinux.flatimage" | xargs -I {} sh -c 'file {}; sha256sum {}; du -sh {}'
  fi
 docker rmi "artixlinux/artixlinux:latest" --force
 popd >/dev/null 2>&1
#-------------------------------------------------------#