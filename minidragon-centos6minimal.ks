install
text
skipx
url --url http://mirror.cogentco.com/pub/linux/centos/6/os/x86_64/
repo --name=updates	--baseurl=http://mirror.cogentco.com/pub/linux/centos/6/updates/x86_64/
repo --name=rpmfusion	--baseurl=http://pkgs.repoforge.org/rpmforge-release/
# repo --name=epel	--baseurl=http://download.fedoraproject.org/pub/epel/6/x86_64/
lang en_US.UTF-8
keyboard us
rootpw --iscrypted <CHANGE>
user --name=corey --password=<CHANGE> --iscrypted
firewall --service=ssh

# System authorization information
authconfig --enableshadow --passalgo=sha512

selinux --enforcing
#selinux --disabled
timezone --utc America/Denver
# System bootloader configuration
bootloader --location=mbr --append="crashkernel=auto rhgb quiet noipv6 "
# Clear the Master Boot Record
zerombr
# Installation logging level
logging --level=info

# Partition clearing information
clearpart --all --initlabel


services --enabled=network,ntpd,ntpdate


reboot


# // Cobbler Scripted PHLY Defaults
# Import partition info
# partition selection
%include /tmp/partinfo
# // End Cobbler Scripted PHLY Defaults



# PRE-INSTALL SECTION -- SCRIPTS RUN BEFORE INSTALLATION
%pre
# Begin Logging
set -x -v
exec 1>/tmp/ks-pre.log 2>&1

# Once root's homedir is there, copy over the log.
while : ; do
    sleep 10
    if [ -d /mnt/sysimage/root ]; then
        cp /tmp/ks-pre.log /mnt/sysimage/root/
        logger "Copied %pre section log to system"
        break
    fi
done &


# Pre partition select
# partition details calculation

# Determine how many drives we have
set $(list-harddrives)
let numd=$#/2
d1=$1
d2=$3

# Print partition info to file to be imported in the main section of the kickstart
cat << EOF > /tmp/partinfo
part /boot --fstype ext4 --fsoptions="noatime" --size 200 --recommended
part pv.00 --asprimary --grow --size=1 --ondisk=$d1
volgroup vg_p01appbugz0190 pv.00
logvol swap	--vgname=vg_p01appbugz0190 --fstype="swap" --size=512 --name=lv_swap
ogvol /var	--vgname=vg_p01appbugz0190 --fstype="ext4" --fsoptions="noatime" --grow --size=512 --name=lv_var
logvol /home	--vgname=vg_p01appbugz0190 --fstype="ext4" --fsoptions="noatime" --size=256 --name=lv_home
logvol /opt	--vgname=vg_p01appbugz0190 --fstype="ext4" --fsoptions="noatime" --size=32 --name=lv_opt
logvol /tmp	--vgname=vg_p01appbugz0190 --fstype="ext4" --fsoptions="noatime" --size=512 --name=lv_tmp
logvol /	--vgname=vg_p01appbugz0190 --fstype="ext4" --fsoptions="noatime" --size=3072 --name=lv_root
logvol /usr/local --vgname=vg_p01appbugz0190 --fstype="ext4" --fsoptions="noatime" --size=512 --name=lv_usrlocal
%end

%packages --nobase
# epel-release
# rpmforge-release
yum
# acpid
at
vixie-cron
cronie-noanacron
crontabs
dmidecode
logrotate
lsof
man
man-pages
ntp
ntpdate
openssh-clients
openssh-server
rsync
# screen
sendmail
sudo
sysstat
telnet
tmpwatch
traceroute
unzip
vim-enhanced
which
wget

# SELinux management tools
policycoreutils-python



-postfix
%end


# POST-INSTALL SECTION -- SCRIPTS RUN AFTER INSTALLATION
%post
exec < /dev/tty3 > /dev/tty3
chvt 3
echo
echo "#----------------------------#"
echo "# Running Post Configuration #"
echo "#----------------------------#"
(
set -x -v


# Get my IP address and hostname
# service network restart
export IP_ADDRESS=`ifconfig | grep 'inet addr:' | grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1 }'`
export HOSTNAME=`hostname`
export SHORTNAME=`hostname -s`

# Begin kinnick customizations

# Configure, enable, and start ntp
# remove ipv6 entry
sed -ci '/restrict\ -6..*/d' /etc/ntp.conf
# Virts may reset their system clocks on a hard power cycle,
# so we will force a time sync at each boot
cat << EOF >> /etc/rc.d/rc.local

# Sync time and start ntpd
ntpdate 0.centos.pool.ntp.org
ntpdate 0.centos.pool.ntp.org
ntpdate 0.centos.pool.ntp.org
service ntpd start
EOF

wget "http://hawkeye.kinnick/kickstart_customizations.sh" --output-document="/root/kickstart_customizations.sh"
bash /tmp/kickstart_customizations.sh

# Start post install kernel options update
/sbin/grubby --update-kernel=`/sbin/grubby --default-kernel` --args="noipv6 amd_iommu=on"
if ( grep -q '6\.' /etc/redhat-release ) ; then
	/usr/sbin/plymouth-set-default-theme details
	/usr/libexec/plymouth/plymouth-update-initrd
fi
# End post install kernel options update

# echo "must schedule yum update as some problems can occur if doing too soon at provision time"
# service atd start
# echo "/usr/bin/yum update -y; /sbin/init 6" | at now + 4 minutes
yum update -y

# Close out %post logging
) 2>&1 | /usr/bin/tee /root/ks-post.log
chvt 1

%end
