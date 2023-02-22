#!/bin/bash

archlinux_repo='https://mirrors.bfsu.edu.cn/archlinux/$repo/os/$arch'
archlinuxcn_repo='https://mirrors.bfsu.edu.cn/archlinuxcn/$arch'

types=(
  bios
  uefi
)

environments=(
  i3
  kde
  deepin
)

init() {
    echo "init"
        systemctl stop reflector

        read -p "Please input root password: " root_password
        read -p "Please input normal username: " username
        read -p "Please input normal user password: " password

        echo "Please select type: "
        select type in ${types[@]}
        do
            case $type in
            "bios")
                echo "bios"
                bios
                break
                ;;
            "uefi")
                echo "uefi"
                uefi
                break
                ;;
            esac
        done

        config_pacman
        echo "Please select desktop environment: "
        select environment in ${environments[@]}
        do
            case $environment in
            "i3")
                echo "i3"
                i3
                break
                ;;
            "kde")
                echo "kde"
                kde
                break
                ;;
            "deepin")
                echo "deepin"
                deepin
                break
                ;;
            esac
        done

        if [ $type = "uefi" ] ;then
            pacstrap /mnt efibootmgr
        fi

    echo 'genfstab start'
        genfstab -U /mnt > /mnt/etc/fstab
    echo 'genfstab end'

    echo 'chroot start'
        arch-chroot /mnt sh -c "
            set -e
            echo 'grub install start'
                sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/g' /etc/default/grub
                if [ $type == \"bios\" ]; then
                    grub-install $disk
                elif [ $type == \"uefi\" ]; then
                    grub-install --efi-directory=/boot/efi --bootloader-id=\"Arch Linux\"
                fi
                grub-mkconfig -o /boot/grub/grub.cfg
            echo 'grub install end'

            echo 'update root password start'
                chsh -s /bin/zsh
                cp /usr/share/oh-my-zsh/zshrc ~/.zshrc
                echo root:$root_password | chpasswd
            echo 'update root password end'

                systemctl enable dhcpcd
            echo 'dhcpcd enabled'

            echo 'nano config update start'
                sed -i '/# include/{s/#//}' /etc/nanorc
                sed -i '/# set constantshow/{s/#//}' /etc/nanorc
                echo 'alias n=nano' >> /etc/profile
                echo 'export EDITOR=nano' >> /etc/profile
            echo 'nano config update end'

            echo 'update locale start'
                sed -i '/#en_US.UTF-8/{s/#//}' /etc/locale.gen
                locale-gen
            echo 'update locale end'

            echo 'add normal user start'
                useradd -m $username -s /bin/zsh
                echo $username:$password | chpasswd
                echo -e '\n$username ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
            echo 'add normal user end'

            echo 'config docker start'
                gpasswd -a $username docker
                systemctl enable docker
            echo 'config docker end'

            echo 'config virtualbox start'
                gpasswd -a $username vboxusers
            echo 'config virtualbox end'

            echo 'config network start'
                systemctl enable NetworkManager
            echo 'config network end'

            echo 'config environment start'
                if [ $environment == \"i3\" ]; then
                    sed -i 's/#greeter-session=example-gtk-gnome/greeter-session=lightdm-slick-greeter/g' /etc/lightdm/lightdm.conf
                    systemctl enable lightdm
                elif [ $environment == \"kde\" ]; then
                    systemctl enable sddm
                elif [ $environment == \"deepin\" ]; then
                    systemctl enable lightdm
                fi
            echo 'config environment end'

            echo 'update db start'
                updatedb
            echo 'update db end'

            su $username -c '
                cp /usr/share/oh-my-zsh/zshrc ~/.zshrc
                mkdir ~/.ssh
                echo -e \"ServerAliveInterval 60\n\nHost *\n StrictHostKeyChecking no\n\nHost vt\n HostName hostname\n Port port\n User user\" > ~/.ssh/config
            '
        "
    echo 'chroot end'

    echo 'umount start'
        umount -R /mnt
    echo 'umount end'

    echo 'system will reboot in 5 seconds'
        sleep 5

    sync
    reboot -f
}

bios() {
    echo 'partition start'
        disk=/dev/sda
        partition=/dev/sda1
        sfdisk --delete $disk

        set -e

        if grep -qs "$partition" /proc/mounts; then
            umount $partition
        fi

        parted -s $disk mklabel msdos
        parted -s $disk mkpart primary ext4 '1 -1'
        mkfs.ext4 -F $partition
        parted -s $disk set 1 boot on
    echo 'partition end'

    echo 'partition monut start'
        mount $partition /mnt
    echo 'partition monut end'
}

uefi() {
    echo 'partition start'
        disk=/dev/sda
        efi=/dev/sda1
        partition=/dev/sda2
        sfdisk --delete $disk

        set -e

        if grep -qs "$partition" /proc/mounts; then
            umount $partition
        fi

        parted -s $disk mklabel gpt
        parted -s $disk mkpart primary fat32 1 512M
        parted -s $disk mkpart primary ext4 '512M -1'
        parted -s $disk set 1 boot on
        mkfs.fat -F32 $efi
        mkfs.ext4 -F $partition
    echo 'partition end'

    echo 'partition monut start'
        mount $partition /mnt
        mkdir -p /mnt/boot/efi
        mount $efi /mnt/boot/efi
    echo 'partition monut end'
}

config_pacman() {
    echo 'pacman config start'
        echo "Server = $archlinux_repo" > /etc/pacman.d/mirrorlist
        sed -i 's/Required DatabaseOptional/Never/g' /etc/pacman.conf
        sed -i '/ParallelDownloads/a ILoveCandy' /etc/pacman.conf
        echo -e "\n[archlinuxcn]" >> /etc/pacman.conf
        echo "Server = $archlinuxcn_repo" >> /etc/pacman.conf
    echo 'pacman config end'
}

i3() {
    echo 'install i3 packages start'
        pacstrap /mnt ${init_packages[@]}
        cp /etc/pacman.conf /mnt/etc/pacman.conf
        pacstrap /mnt ${i3_packages[@]}
        pacstrap /mnt ${common_packages[@]}
    echo 'install i3 packages end'
}

kde() {
    echo 'install kde packages start'
        pacstrap /mnt ${init_packages[@]}
        cp /etc/pacman.conf /mnt/etc/pacman.conf
        pacstrap /mnt ${kde_packages[@]}
        pacstrap /mnt ${common_packages[@]}
    echo 'install kde packages end'
}

deepin() {
    echo 'install deepin packages start'
        pacstrap /mnt ${init_packages[@]}
        cp /etc/pacman.conf /mnt/etc/pacman.conf
        pacstrap /mnt ${deepin_packages[@]}
        pacstrap /mnt ${common_packages[@]}
    echo 'install deepin packages end'
}

init_packages=(
    base
    base-devel
    bash-completion
    dhcpcd
    grub
    linux
    linux-firmware
    nano
)

i3_packages=(
    alsa-utils
    arc-gtk-theme
    arc-icon-theme
    conky
    i3-gaps
    lightdm
    lightdm-slick-greeter
    lxappearance
    mousepad
    network-manager-applet
    pavucontrol
    picom
    py3status
    python-pytz
    python-tzlocal
    qt5ct
    ristretto
    rofi
    thunar
    thunar-archive-plugin
    xarchiver
    xfce4-clipman-plugin
    xfce4-power-manager
    xfce4-terminal
    xorg-xkill
)

kde_packages=(
    ark
    dolphin
    filelight
    gwenview
    kate
    kinfocenter
    konsole
    okular
    phonon-qt5-vlc
    plasma-desktop
    plasma-nm
    plasma-pa
    sddm
    yakuake
)

deepin_packages=(
    deepin
    deepin-screenshot
    deepin-terminal
)

common_packages=(
    android-tools
    ctop
    fcitx5-im
    fcitx5-chinese-addons
    flameshot
    docker
    docker-compose
    github-cli
    godot
    gradle
    gvfs
    gvfs-mtp
    htop
    httpie
    inetutils
    intellij-idea-ultimate-edition
    intellij-idea-ultimate-edition-jre
    iredis
    jdk-openjdk
    jdk8-openjdk
    jq
    lazygit
    links
    lrzsz
    man-pages
    maven
    mlocate
    mycli
    neofetch
    net-tools
    nodejs
    noto-fonts
    noto-fonts-cjk
    npm
    ntfs-3g
    oh-my-zsh-git
    openjdk-src
    openjdk8-src
    openssh
    p7zip
    pikaur
    pm2
    postman-bin
    ps_mem
    pulseaudio
    ranger
    rsync
    scrcpy
    sqlitebrowser
    sshfs
    tree
    virtualbox-ext-oracle
    virtualbox-guest-iso
    virtualbox-host-modules-arch
    wget
    xorg-server
    yarn
    zsh
    zssh
)

aur_packages=(
    fcitx5-breeze
    google-chrome
    resp-app
    visual-studio-code-bin
    vue-cli
)

setup() {
    read -p "Please input hostname: " hostname
    echo 'update hostname start'
        hostnamectl set-hostname $hostname
    echo 'update hostname end'

    echo 'update timedate start'
        timedatectl set-timezone Asia/Shanghai
        timedatectl set-ntp true
    echo 'update timedate end'

    echo 'update locale start'
        localectl set-locale en_US.UTF-8
    echo 'update locale end'

    echo 'install aur packages start'
        pikaur -S --needed --noconfirm ${aur_packages[@]}
    echo 'install aur packages end'
}

$1
