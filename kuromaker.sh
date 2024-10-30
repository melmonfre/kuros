#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Este script requer permissões de root. Execute-o com sudo."
    exit 1
fi

cat << "EOF"

#########################################################################
#                  _  __     ____             _  ___ _                  #
#                 | |/ /    |  _ \  _____   _| |/ (_) |_                #
#                 | ' /_____| | | |/ _ \ \ / / ' /| | __|               #
#                 | . \_____| |_| |  __/\ V /| . \| | |_                # 
#                 |_|\_\    |____/ \___| \_/ |_|\_\_|\__|               #
#                                                                       #
# Criado Por: Melissa Monfre                                            #
#                                                                       #
# Versão KurOS 1.9.86-b                                                 #
#                                                                       #
#        K-Devkit é um software para desenvolvimento do KurOS           #
#                                                                       #
#########################################################################
EOF

mirror="https://distfiles.gentoo.org/releases/amd64/autobuilds/20241027T164832Z/stage3-amd64-desktop-openrc-20241027T164832Z.tar.xz"
stage3="$HOME/gentoo"
user="kuros"
passwd="kuros"
iso_date=$(date +%d-%m-%Y)
iso_name="KurOS-Alpha-$iso_date.iso"
iso_dir="$HOME/kuroiso"
checkpoint_file="$HOME/kuroiso/kuros_checkpoint"
max_retries=5
cleanup_needed=true

function cleanup {
    if [ "$cleanup_needed" = true ] && [ -d "$stage3" ]; then
        rm -rf "$stage3" || true
    fi
}

trap cleanup EXIT

function check_checkpoint {
    local step_name="$1"
    if [[ -f "$checkpoint_file" ]] && grep -q "$step_name" "$checkpoint_file"; then
        echo "Etapa '$step_name' já concluída. Pulando..."
        return 0
    fi
    return 1
}

function add_checkpoint {
    echo "$1" >> "$checkpoint_file"
}

function retry_command {
    local retries="$max_retries"
    until "$@"; do
        ((retries--))
        if [ "$retries" -le 0 ]; then
            echo "Falhou após $max_retries tentativas."
            exit 1
        fi
        sleep 5
    done
}

mkdir -p "$stage3" "$iso_dir" || exit 1

check_checkpoint "download_stage3" || {
    retry_command wget "$mirror" -O "$HOME/stage3.tar.xz" || exit 1
    add_checkpoint "download_stage3"
}

check_checkpoint "extract_stage3" || {
    tar xpvf "$HOME/stage3.tar.xz" -C "$stage3" --xform='s|.*|stage3-amd64|' || exit 1
    add_checkpoint "extract_stage3"
}

mount --rbind /dev "$stage3/dev"
mount --make-rslave "$stage3/dev"
mount -t proc /proc "$stage3/proc"
mount --rbind /sys "$stage3/sys"
mount --make-rslave "$stage3/sys"
mount --bind /run "$stage3/run"
cp /etc/resolv.conf "$stage3/etc/"

cat << EOF > "$stage3/setup_kuro.sh"
#!/bin/bash
emerge-webrsync
echo "America/Sao_Paulo" > /etc/timezone
emerge --config sys-libs/timezone-data
eselect profile set 5
emerge -uDN @world
useradd -m -G wheel -s /bin/bash "$user"
echo "$user:$passwd" | chpasswd
echo "$user ALL=(ALL) ALL" > /etc/sudoers.d/$user
echo "exec gnome-session" > /home/$user/.xinitrc
echo "exec gnome-session" > /root/.xinitrc
sed -i '/^# %wheel ALL=(ALL) ALL/s/^# //' /etc/sudoers
echo 'CONFIG_TASK_DELAY_ACCT=y' >> /etc/portage/make.conf
emerge sys-kernel/gentoo-sources
emerge sys-kernel/genkernel
genkernel all
emerge sys-kernel/linux-firmware net-misc/networkmanager www-client/firefox-bin gnome-base/gnome-light x11-apps/xinit
rc-update add dbus default
rc-update add xdm default
rc-update add NetworkManager default
eselect xorg-server set 1
emerge x11-drivers/xf86-input-libinput x11-drivers/xf86-video-vesa x11-drivers/xf86-video-amdgpu
rc-update add gdm default
gdm
emerge sys-boot/grub:2
grub-install
grub-mkconfig -o /boot/grub/grub.cfg
EOF

chmod +x "$stage3/setup_kuro.sh"

chroot "$stage3" /bin/bash -c "/setup_kuro.sh" || { echo "Erro no chroot."; cleanup_needed=false; exit 1; }

cd "$iso_dir"
mkdir -p livecd/boot/grub

cat << EOF > livecd/boot/grub/grub.cfg
set timeout=10
set default=0

menuentry "KurOS Live" {
    linux /vmlinuz root=/dev/ram0 init=/linuxrc looptype=squashfs loop=/image.squashfs cdroot quiet
    initrd /initrd.img
}
EOF

mksquashfs "$stage3" livecd/image.squashfs -e boot
cp "$stage3/boot/vmlinuz"* livecd/boot/vmlinuz
cp "$stage3/boot/initramfs"* livecd/boot/initrd.img

xorriso -as mkisofs -o "$iso_dir/$iso_name" -b boot/grub/i386-pc/eltorito.img \
  -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table livecd

