#!/bin/env bash

##################################################################################
# This is the entry point for configuring the system.                            #
# Source https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox   #
# Updated by Afiniel for yiimpool use...                                         #
##################################################################################

clear
source /etc/functions.sh
source /etc/yiimpool.conf
source $STORAGE_ROOT/yiimp/.yiimp.conf
source $HOME/yiimp_install_script/yiimp_single/.wireguard.install.cnf

set -eu -o pipefail

function print_error {
	read line file <<<$(caller)
	echo "An error occurred in line $line of file $file:" >&2
	sed "${line}q;d" "$file" >&2
}
trap print_error ERR

function term_art() {
  echo "This is a custom term art function"
echo -e "$MAGENTA    <-------------------------->$COL_RESET"
echo -e "$YELLOW     <-- System Configuration -->$COL_RESET"
echo -e "$MAGENTA    <-------------------------->$COL_RESET"
}

# Set timezone
echo
echo -e "$YELLOW =>  Setting TimeZone to UTC <= $COL_RESET"
if [ ! -f /etc/timezone ]; then
	echo "Setting timezone to UTC."
	echo "Etc/UTC" /etc/timezone >sudo
	restart_service rsyslog
fi
echo

# Add repository
echo -e "$MAGENTA =>  Adding the required repsoitories <= $COL_RESET"
if [ ! -f /usr/bin/add-apt-repository ]; then
	echo
	echo -e "$MAGENTA =>  Installing add-apt-repository  <= $COL_RESET"
	hide_output sudo apt-get update
	hide_output sudo apt-get -y install software-properties-common
fi
echo

# PHP 7.3
echo -e "$MAGENTA =>  Installing Ondrej PHP PPA <= $COL_RESET"
if [ ! -f /etc/apt/sources.list.d/ondrej-php-bionic.list ]; then
	hide_output sudo add-apt-repository -y ppa:ondrej/php
	hide_output sudo apt-get -y update
	echo -e "$GREEN Done$COL_RESET"
	# hide_output sudo apt-get -y install software-properties-common
fi

# CertBot
echo
echo -e "$MAGENTA =>  Installing CertBot PPA <= $COL_RESET"
hide_output sudo add-apt-repository -y ppa:certbot/certbot
hide_output sudo apt-get -y update
echo -e "$GREEN Done$COL_RESET"

# MariaDB
echo
echo -e "$MAGENTA =>  Installing MariaDB <= $COL_RESET"
hide_output sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8
if [[ ("$DISTRO" == "18") ]]; then
	sudo add-apt-repository 'deb [arch=amd64,arm64,i386,ppc64el] http://mirror.one.com/mariadb/repo/10.4/ubuntu bionic main' >/dev/null 2>&1
else
	sudo add-apt-repository 'deb [arch=amd64,arm64,ppc64el] http://mirror.one.com/mariadb/repo/10.4/ubuntu xenial main' >/dev/null 2>&1
fi
echo -e "$GREEN Done$COL_RESET"

# Upgrade System Files
hide_output sudo apt-get update

echo
echo -e "$YELLOW =>  Upgrading system packages <= $COL_RESET"
if [ ! -f /boot/grub/menu.lst ]; then
	apt_get_quiet upgrade
else
	sudo rm /boot/grub/menu.lst
	hide_output sudo update-grub-legacy-ec2 -y
	apt_get_quiet upgrade
fi

# Dist Upgrade
apt_get_quiet dist-upgrade

apt_get_quiet autoremove

echo
echo -e "$MAGENTA =>  Installing Base system packages <= $COL_RESET"
apt_install python3 python3-dev python3-pip \
	wget curl git sudo coreutils bc \
	haveged pollinate unzip \
	unattended-upgrades cron ntp fail2ban screen rsyslog lolcat

# ### Seed /dev/urandom
echo -e "$GREEN Done$COL_RESET"
echo
echo -e "$YELLOW =>  Initializing system random number generator <= $COL_RESET"
hide_output dd if=/dev/random of=/dev/urandom bs=1 count=32 2>/dev/null
hide_output sudo pollinate -q -r
echo -e "$GREEN Done$COL_RESET"

echo
echo -e "$YELLOW =>  Initializing UFW Firewall <= $COL_RESET"
set +eu +o pipefail
if [ -z "${DISABLE_FIREWALL:-}" ]; then
	# Install `ufw` which provides a simple firewall configuration.
	apt_install ufw
	echo
	echo -e "$YELLOW => Allow incoming connections to SSH <= $COL_RESET"
	echo
	echo
	ufw_allow ssh
	sleep 0.5
	echo -e "$YELLOW ssh port:$GREEN OPEN $COL_RESET"
	echo
	sleep 0.5
	ufw_allow http
	echo -e "$YELLOW http port:$GREEN OPEN $COL_RESET"
	echo
	sleep 0.5
	ufw_allow https
	echo -e "$YELLOW https port:$GREEN OPEN $COL_RESET"
	echo
	# ssh might be running on an alternate port. Use sshd -T to dump sshd's #NODOC
	# settings, find the port it is supposedly running on, and open that port #NODOC
	# too. #NODOC
	SSH_PORT=$(sshd -T 2>/dev/null | grep "^port " | sed "s/port //") #NODOC
	if [ ! -z "$SSH_PORT" ]; then
		if [ "$SSH_PORT" != "22" ]; then

			echo -e "$YELLOW => Allow incoming connections to SSH <= $COL_RESET"
			echo
			echo -e "$YELLOW Opening alternate SSH port:$GREEN $SSH_PORT $COL_RESET"
			echo
			ufw_allow $SSH_PORT
			sleep 0.5
			echo
			echo -e "$YELLOW http port:$GREEN OPEN $COL_RESET"
			ufw_allow http
			sleep 0.5
			echo
			echo -e "$YELLOW https port:$GREEN OPEN $COL_RESET"
			ufw_allow https
			sleep 0.5
			echo

		fi
	fi

	hide_output sudo ufw --force enable
fi
set -eu -o pipefail
echo
echo -e "$MAGENTA =>  Installing YiiMP Required system packages <= $COL_RESET"
if [ -f /usr/sbin/apache2 ]; then
	echo Removing apache...
	hide_output apt-get -y purge apache2 apache2-*
	hide_output apt-get -y --purge autoremove
fi

hide_output sudo apt-get update

if [[ ("$DISTRO" == "18") ]]; then
apt_install php7.3-fpm php7.3-opcache php7.3-fpm php7.3 php7.3-common php7.3-gd \
php7.3-mysql php7.3-imap php7.3-cli php7.3-cgi \
php-pear php-auth-sasl mcrypt imagemagick libruby \
php7.3-curl php7.3-intl php7.3-pspell php7.3-recode php7.3-sqlite3 \
php7.3-tidy php7.3-xmlrpc php7.3-xsl memcached php-memcache \
php-imagick php-gettext php7.3-zip php7.3-mbstring \
fail2ban ntpdate python3 python3-dev python3-pip \
curl git sudo coreutils pollinate unzip unattended-upgrades cron \
pwgen libgmp3-dev libmysqlclient-dev libcurl4-gnutls-dev \
libkrb5-dev libldap2-dev libidn11-dev gnutls-dev librtmp-dev \
build-essential libtool autotools-dev automake pkg-config libevent-dev bsdmainutils libssl-dev \
automake cmake gnupg2 ca-certificates lsb-release nginx certbot libsodium-dev \
libnghttp2-dev librtmp-dev libssh2-1 libssh2-1-dev libldap2-dev libidn11-dev libpsl-dev libkrb5-dev php7.3-memcache php7.3-memcached memcached \
php8.1-mysql
else
apt_install php7.3-fpm php7.3-opcache php7.3-fpm php7.3 php7.3-common php7.3-gd \
php7.3-mysql php7.3-imap php7.3-cli php7.3-cgi \
php-pear php-auth-sasl mcrypt imagemagick libruby \
php7.3-curl php7.3-intl php7.3-pspell php7.3-recode php7.3-sqlite3 \
php7.3-tidy php7.3-xmlrpc php7.3-xsl memcached php-memcache \
php-imagick php-gettext php7.3-zip php7.3-mbstring \
fail2ban ntpdate python3 python3-dev python3-pip \
curl git sudo coreutils pollinate unzip unattended-upgrades cron \
pwgen libgmp3-dev libmysqlclient-dev libcurl4-gnutls-dev \
libkrb5-dev libldap2-dev libidn11-dev gnutls-dev librtmp-dev \
build-essential libtool autotools-dev automake pkg-config libevent-dev bsdmainutils libssl-dev \
libpsl-dev libnghttp2-dev automake cmake gnupg2 ca-certificates lsb-release nginx certbot libsodium-dev \
libnghttp2-dev librtmp-dev libssh2-1 libssh2-1-dev libldap2-dev libidn11-dev libpsl-dev libkrb5-dev php7.3-memcache php7.3-memcached memcached \
php8.1-mysql
fi

# Suppress Upgrade Prompts
# When Ubuntu 20 comes out, we don't want users to be prompted to upgrade,
# because we don't yet support it.
if [ -f /etc/update-manager/release-upgrades ]; then
sudo editconf.py /etc/update-manager/release-upgrades Prompt=never
sudo rm -f /var/lib/ubuntu-release-upgrader/release-upgrade-available
fi

# fix CDbConnection failed to open the DB connection.
# echo
echo -e "$CYAN => Fixing DBconnection issue $COL_RESET"
# apt_install php8.1-mysql
sudo update-alternatives --set php /usr/bin/php7.3
echo

echo
echo -e "$CYAN =>  Clone Kudaraidee Yiimp Repo <= $COL_RESET"
hide_output sudo git clone ${YiiMPRepo} $STORAGE_ROOT/yiimp/yiimp_setup/yiimp
if [[ ("$CoinPort" == "yes") ]]; then
	cd $STORAGE_ROOT/yiimp/yiimp_setup/yiimp
	sudo git fetch
	sudo git checkout dev >/dev/null 2>&1
fi

hide_output service nginx restart

set +eu +o pipefail
cd $HOME/yiimp_install_script/yiimp_single
