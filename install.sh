#!/bin/bash

prepare() {
    # 分区
    DISK=/dev/nvme0n1
    ESP=/dev/nvme0n1p1
    ROOT=/dev/nvme0n1p2
    parted $DISK mklabel gpt
    parted $DISK mkpart primary 1 512M
    parted $DISK mkpart primary '512M -1' # -1转义
    parted $DISK set 1 boot on

    # 格式化
    mkfs.fat -F32 $ESP
    mkfs.ext4 $ROOT

    # 挂载
    mount $ROOT /mnt
    mkdir -p /mnt/boot/efi
    mount $ESP /mnt/boot/efi

    # archlinux源
    echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/x86_64' > /etc/pacman.d/mirrorlist

    # 安装
    pacstrap /mnt base base-devel bash-completion grub efibootmgr
    genfstab -U -p /mnt > /mnt/etc/fstab

    # 配置grub
    arch-chroot /mnt grub-install --efi-directory=/boot/efi --bootloader-id=Arch
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    arch-chroot /mnt sed '/set timeout=5/{s/5/0/}' -i /boot/grub/grub.cfg

    # 后面还会用到
    cp install.sh /mnt/root

    # 重启
    umount /mnt/boot/efi
    umount /mnt
    reboot -f
}

pgk=(
    adobe-source-han-sans-cn-fonts
    adobe-source-han-sans-jp-fonts
    adobe-source-han-sans-kr-fonts
    anaconda
    android-apktool
    android-emulator
    android-file-transfer
    android-ndk
    android-platform
    android-sdk-build-tools
    android-studio
    android-support
    android-support-repository
    android-tools
    apache-tools
    arandr
    ark
    chromium
    deepin-screenshot
    deepin-screen-recorder
    # dkms
    docker
    docker-compose
    docker-machine
    dolphin
    fcitx-im
    fcitx-sogoupinyin
    filelight
    filezilla
    gimp
    git
    gitkraken
    gnome-keyring
    gwenview
    gradle
    hydra
    intellij-idea-ultimate-edition
    intellij-idea-ultimate-edition-jre
    jdk8
    john
    jq
    kate
    kcm-fcitx
    kdialog
    kinfocenter
    konsole
    libsodium
    # linux-headers
    lrzsz
    maven
    metasploit
    mlocate
    mycli
    netease-cloud-music
    net-tools
    nmap
    nodejs
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    npm
    ntfs-3g
    okteta
    okular
    openntpd
    openssh
    pepper-flash
    phonon-qt5-vlc
    plasma-desktop
    plasma-nm
    plasma-pa
    postman-bin
    powerdevil
    powerpill
    # ppsspp
    privoxy
    proxychains-ng
    python-pip
    redis-desktop-manager
    rsync
    sddm
    shadowsocks
    speedtest-cli
    sqlmap
    sublime-text-dev
    teamviewer
    typora
    unrar
    unzip
    user-manager
    virtualbox-ext-oracle
    virtualbox-guest-iso
    virtualbox-host-modules-arch
    vokoscreen-git
    w3m
    wewechat
    wget
    wireshark-qt
    wps-office
    xorg-server
    xorg-xkill
    yakuake
    youtube-dl
    zip
    zsh
)

aur=(
    # 9182eu-dkms
    android-constraint-layout
    android-google-repository
    android-sources-28
    android-x86-64-system-image-28
    archlinux-themes-sddm
    burpsuite
    deepin-wechat
    deepin-wine-thunderspeed
    dex2jar
    dingtalk-electron
    dirbuster
    # jd-gui # build太久
    maltego
    python-genpac
    sqliteman
    ttf-wps-fonts
    # xboxdrv
)

aur() {
    # AUR包代理下载
    proxychains yaourt -S --noconfirm --needed ${aur[@]}
}

setup() {
    # 基本数据
    HOSTNAME='?'
    USERNAME='?'
    PASSWORD='?'
    SS_CONFIG_NAME='?'
    SS_SERVER='?'
    SS_PORT='?'
    SS_PASSWORD='?'
    SS_METHOD='?'

    # archlinuxcn源
    sed '/#Color\|#TotalDownload\|#\[multilib\]/{s/#//}' -i /etc/pacman.conf
    sed 's/Required DatabaseOptional/Never/g' -i /etc/pacman.conf
    sed '94s/#//' -i /etc/pacman.conf # [multilib]
    echo -e '\n[archlinuxcn]\nServer = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/x86_64' >> /etc/pacman.conf
    pacman -Syy --noconfirm archlinuxcn-keyring yaourt

    # 用户
    useradd -m $USERNAME

    # sudo免密码
    echo -e "\n$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    echo $USERNAME:$PASSWORD | chpasswd

    # 安装需要的包
    pacman -S --noconfirm --needed ${pgk[@]}

    # shadowsocks
    mv /etc/shadowsocks/example.json /etc/shadowsocks/$SS_CONFIG_NAME.json
    sed "s/my_server_ip/$SS_SERVER/g" -i /etc/shadowsocks/$SS_CONFIG_NAME.json
    sed "s/8388/$SS_PORT/g" -i /etc/shadowsocks/$SS_CONFIG_NAME.json
    sed "s/mypassword/$SS_PASSWORD/g" -i /etc/shadowsocks/$SS_CONFIG_NAME.json
    sed "s/aes-256-cfb/$SS_METHOD/g" -i /etc/shadowsocks/$SS_CONFIG_NAME.json
    systemctl enable shadowsocks@$SS_CONFIG_NAME.service
    systemctl start shadowsocks@$SS_CONFIG_NAME.service

    # proxychains-ng
    sed '/#quiet_mode/{s/#//}' -i /etc/proxychains.conf # 减少输出
    sed "s/socks4 	127.0.0.1 9050/\nsocks5 127.0.0.1 1080/g" -i /etc/proxychains.conf

    # privoxy
    sed 's/127.0.0.1:8118/0.0.0.0:8118/g' -i /etc/privoxy/config
    echo -e '\nforward-socks5 / 127.0.0.1:1080 .' >> /etc/privoxy/config
    systemctl enable privoxy.service
    systemctl start privoxy.service

    sleep 1s # 配置生效延迟

    # AUR不能用root
    cp install.sh /home/$USERNAME/
    chown $USERNAME:$USERNAME /home/$USERNAME/install.sh
    cd /home/$USERNAME # 权限问题
    su $USERNAME -c "/home/$USERNAME/install.sh aur"

    ##################################################

    # 详细配置
    # 主机
    hostnamectl set-hostname $HOSTNAME

    # 时区
    timedatectl set-timezone Asia/Shanghai

    # 国际化
    sed '/#en_US.UTF-8\|#zh_CN.UTF-8/{s/#//}' -i /etc/locale.gen
    locale-gen
    echo 'LANG=en_US.UTF-8' > /etc/locale.conf

    # 基本文件夹
    su $USERNAME -c 'cd ~ && mkdir Data Documents Downloads Music Pictures Project Software Temp Videos .gradle'

    # anaconda
    echo 'export PATH=/opt/anaconda/bin:$PATH' >> /etc/profile

    # android
    echo 'export ANDROID_HOME=/opt/android-sdk' >> /etc/profile
    ln -s /opt/android-ndk /opt/android-sdk/ndk-bundle
    chown -R $USERNAME:$USERNAME /opt/android-sdk # Android Studio需要写文件到这些目录，AUR里找不到包
    # chown -R $USERNAME:$USERNAME /opt/android-ndk

    # deepin-screen-recorder
    su $USERNAME -c "mkdir -p ~/.config/deepin/deepin-screen-recorder"
    su $USERNAME -c "echo -e \"[fileformat]\nsave_directory=/home/$USERNAME/Videos\" > ~/.config/deepin/deepin-screen-recorder/config.conf"

    # docker
    gpasswd -a $USERNAME docker
    mkdir /etc/systemd/system/docker.service.d
    echo -e '[Service]\nEnvironment="HTTP_PROXY=127.0.0.1:8118"\nEnvironment="HTTPS_PROXY=127.0.0.1:8118"' > /etc/systemd/system/docker.service.d/proxy.conf # 即使官方中国仓库或阿里云也不好使
    systemctl enable docker.service

    # fcitx
    su $USERNAME -c "echo -e 'export GTK_IM_MODULE=fcitx\nexport QT_IM_MODULE=fcitx\nexport XMODIFIERS=@im=fcitx' > ~/.xprofile"

    # gradle
    echo -e "systemProp.http.proxyHost=127.0.0.1\nsystemProp.http.proxyPort=8118\nsystemProp.https.proxyHost=127.0.0.1\nsystemProp.https.proxyPort=8118" > ~/.gradle/gradle.properties

    # jdk
    echo 'export JAVA_HOME=/usr/lib/jvm/java-8-jdk' >> /etc/profile

    # mlocate
    updatedb

    # nano
    sed '48s/# //' -i /etc/nanorc # 行号
    sed '262s/# //' -i /etc/nanorc # 代码高亮

    # nodejs
    proxychains npm i -g cnpm --registry=https://registry.npm.taobao.org
    proxychains npm i -g hexo-cli

    # openntpd
    systemctl enable openntpd.service
    systemctl start openntpd.service

    # openssh
    mkdir ~/.ssh
    echo "ServerAliveInterval 60" > ~/.ssh/config

    # plasma-nm
    systemctl enable NetworkManager.service

    # privoxy
    sed 's/127.0.0.1:8118/0.0.0.0:8118/g' -i /etc/privoxy/config
    echo -e '\nforward-socks5 / 127.0.0.1:1080 .' >> /etc/privoxy/config
    systemctl enable privoxy.service
    systemctl start privoxy.service

    # python-genpac
    su $USERNAME -c "genpac --format=pac --pac-proxy=\"SOCKS5 127.0.0.1:1080\" > ~/.pac"

    # sddm
    sddm --example-config > /etc/sddm.conf
    sed '/Current=/{s/=/=archlinux-simplyblack/}' -i /etc/sddm.conf # 主题
    systemctl enable sddm.service

    # teamviewer
    systemctl enable teamviewerd.service

    # virtualbox
    gpasswd -a $USERNAME vboxusers

    # wireshark
    gpasswd -a $USERNAME wireshark

    # zsh
    echo $PASSWORD | sudo -S su $USERNAME -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
    reboot -f
}

$1
