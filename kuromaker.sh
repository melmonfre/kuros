#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Este script requer permissões de root. Por favor, execute com sudo."
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
# Versão KurOS 1.9.94-z                                                 #
#                                                 	                #
#        K-Devkit é um software para desenvolvimento do KurOS           #
#                                                                       #
#########################################################################
EOF

mirror="https://distfiles.gentoo.org/releases/amd64/autobuilds/20241027T164832Z/stage3-amd64-desktop-openrc-20241027T164832Z.tar.xz"
stage3="/run/media/mel/GEnto/gentoo"
user="kuros"
iso_date=$(date +%d-%m-%Y)
iso_name="KurOS-Alpha-$iso_date.iso"
iso_dir="/run/media/mel/GEnto/kuroiso"
checkpoint_file="$iso_dir/kuros_checkpoint"
cleanup_needed=true
max_retries=5

# Função para desmontar os pontos de montagem
function cleanup_mounts {
    umount -l "$stage3/dev" || true
    umount -l "$stage3/proc" || true
    umount -l "$stage3/sys" || true
    umount -l "$stage3/tmp" || true
    umount -l "$stage3/run" || true
}

# Função de limpeza principal
function cleanup {
    if [ "$cleanup_needed" = true ]; then
        read -p "Você deseja limpar o diretório de trabalho? (s/n): " resposta
        if [[ "$resposta" == "s" ]]; then
            echo "Limpando diretório temporário..."
            rm -rf "$stage3" latest-stage3-amd64-desktop-openrc.tar.xz
        else
            echo "Manutenção do diretório de trabalho, não será limpo."
        fi
    fi
    cleanup_mounts  # Chama a função de desmontagem
}

trap cleanup EXIT

function retry_command {
    local retries="$max_retries"
    until "$@"; do
        ((retries--))
        if [ "$retries" -le 0 ]; then
            echo "Falhou após $max_retries tentativas: $@"
            return 1
        fi
        sleep 5
    done
}

mkdir -p "$iso_dir"
touch "$checkpoint_file"

retry_command pacman -Sy --needed arch-install-scripts squashfs-tools xorriso dosfstools gptfdisk wget curl || { echo "Falha ao instalar pacotes no Arch"; exit 1; }

mkdir -p "$stage3"
cd "$stage3" || { echo "Erro ao acessar o diretório $stage3"; exit 1; }

retry_command wget "$mirror" -O stage3-amd64-desktop-openrc.tar.xz

echo "Extraindo o stage 3..."
tar xpvf stage3-amd64-desktop-openrc.tar.xz || { echo "Erro na extração do stage 3"; exit 1; }

mount --rbind /dev "$stage3/dev"
mount --make-rslave "$stage3/dev"
mount -t proc /proc "$stage3/proc"
mount --rbind /sys "$stage3/sys"
mount --make-rslave "$stage3/sys"
mount --rbind /tmp "$stage3/tmp"
mount --bind /run "$stage3/run"

cp /etc/resolv.conf "$stage3/etc/"

chroot "$stage3" /bin/bash <<EOF
env-update && source /etc/profile
export PS1="(chroot) \$PS1"
emerge-webrsync
eselect profile set default/linux/amd64/23.0/desktop/gnome	
emerge sys-kernel/gentoo-sources sys-apps/pciutils sys-apps/usbutils net-misc/networkmanager www-client/firefox-bin
emerge x11-base/xorg-drivers x11-drivers/xf86-video-vesa x11-drivers/xf86-video-fbdev media-libs/mesa
emerge gnome-base/gnome-light gnome-base/gdm

# Configurar o login automático para o GDM
if [ ! -f /etc/gdm/custom.conf ]; then
    touch /etc/gdm/custom.conf
fi
cat <<EOL >> /etc/gdm/custom.conf
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=$user
EOL

# Adicionar serviços ao OpenRC
rc-update add gdm default
rc-update add NetworkManager default

useradd -m -G users,wheel,video,audio -s /bin/bash $user
passwd -d $user  # Remove a senha do usuário
passwd -d root   # Remove a senha do usuário root (não recomendado para segurança)
EOF

# Desmontar os pontos de montagem
cleanup_mounts

mkdir -p "$iso_dir/livecd"
cp -R "$stage3"/* "$iso_dir/livecd/"
mkdir -p "$iso_dir/livecd/boot/grub"

cat << "EOF" > "$iso_dir/livecd/boot/grub/grub.cfg"
set timeout=10
set default=0
menuentry "KurOS Live" {
    linux /vmlinuz
    initrd /initrd.img
    boot
}
EOF

retry_command xorriso -as mkisofs -o "$iso_dir/$iso_name" -R -J -V "KurOS" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table "$iso_dir/livecd"
echo "ISO gerada em $iso_dir/$iso_name"
cleanup_needed=false
