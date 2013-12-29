# linux ks=http://10.3.1.101/ks.cfg ksdevice=eth0 ip=dhcp netmask=255.255.255.0 gateway=10.3.1.1
# asknetwork ks=http://10.3.1.101/ks.cfg
network --device=eth0 --bootproto=dhcp --hostname=hawkeye.kinnick --onboot=yes --noipv6

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

part /boot --fstype ext4 --fsoptions="noatime,data=writeback,commit=15,nodiratime"
# System authorization information
authconfig --enableshadow --passalgo=sha512

selinux --enforcing
# selinux --disabled
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
cat << EOF > /tmp/partinfo" --size 200 --recommended
part pv.00 --asprimary --grow --size=1 --ondisk=$d1
volgroup vg_hawkeye pv.00
logvol swap --vgname=vg_hawkeye --fstype="swap" --size=512 --name=lv_swap
logvol /var  --vgname=vg_hawkeye --fstype="ext4" --fsoptions="noatime,nodiratime,data=writeback,commit=15" --size=2048 --name=lv_var
logvol /home    --vgname=vg_hawkeye --fstype="ext4" --fsoptions="noatime,nodiratime,data=writeback,commit=15" --size=256 --name=lv_home
logvol /opt --vgname=vg_hawkeye --fstype="ext4" --fsoptions="noatime,nodiratime,data=writeback,commit=15," --size=32 --name=lv_opt
# logvol /tmp	--vgname=vg_hawkeye --fstype="ext4" --fsoptions="noatime,nodiratime,data=writeback,commit=15" --size=512 --name=lv_tmp
logvol /	--vgname=vg_hawkeye --fstype="ext4" --fsoptions="noatime,nodiratime,commit=15" --size=3072 --name=lv_root
logvol /usr/local --vgname=vg_hawkeye --fstype="ext4" --fsoptions="noatime,nodiratime,data=writeback,commit=15" --size=512 --name=lv_usrlocal
logvol /var/log --vgname=vg_hawkeye --fstype="ext4" --fsoptions="noatime,nodiratime,data=writeback,commit=15" --size=512 --name=lv_varlog
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

# kickstart customizations
echo noop > /sys/block/sda/queue/scheduler

# add tmpfs mounts
cat >>/etc/fstab<<EOF
tmpfs                   /tmp                tmpfs   size=256M       0 0
tmpfs                   /var/tmp            tmpfs   size=128M        0 0
tmpfs                   /var/run            tmpfs   size=2M        0 0
EOF

# https://wiki.archlinux.org/index.php/Solid_State_Drives#Swap_Space_on_SSDs
echo 1 > /proc/sys/vm/swappiness
echo "
vm.swappiness=1
vm.vfs_cache_pressure=50" >> /etc/sysctl.conf

# schedule fstrim command
sed -ci 's/issue_discards\ =\ 0/issue_discards\ =\ 1/g' /etc/lvm/lvm.conf
mkdir /usr/local/scripts
cat << EOF >> /usr/local/scripts/trim
#!/bin/bash
LOG=/var/log/trim.log
for MOUNT in $(df -h | grep mapper | awk '{print $6}') ; do
  fstrim -v ${MOUNT} >> ${LOG}
done
EOF
chmod 755 /usr/local/scripts/trim
crontab -l > mycron
#echo new cron into cron file
echo "0 23 * * * /usr/local/scripts/trim" >> mycron
# install new cron file
crontab mycron
rm mycron

###### SECURITY CONFIG ######
# Configure sudo for user
cat << EOF >> /etc/sudoers
# For me
corey ALL=(ALL) NOPASSWD: ALL
EOF

# Disable root SSH access
# Keep port forwarding (proxy from work through ssh tunnel)
sed -ci 's/^\#PermitRootLogin.*/PermitRootLogin\ no/' /etc/ssh/sshd_config
sed -ci 's/^\#AllowTcpForwarding.*/AllowTcpForwarding\ no/' /etc/ssh/sshd_config
# sed -ci 's/^X11Forwarding\ yes.*/X11Forwarding\ no/' /etc/ssh/sshd_config
sed -ci 's/^\#PermitTunnel\ no/PermitTunnel\ no/' /etc/ssh/sshd_config
echo "AllowUsers corey" >> /etc/ssh/sshd_config

# we'd rather not use /opt
(umask 222 ; cat << EOF > /opt/README
Please install local applications under /usr/local instead of /opt
EOF
)

# add entry for the local machine to the hosts file
echo "$IP_ADDRESS       $HOSTNAME $SHORTNAME" >> /etc/hosts
echo "repair the localhost entry in the hosts file"
sed -ci s/^127\.0\.0\.1.*/127\.0\.0\.1\ \ \ localhost.localdomain\ localhost/ /etc/hosts

# disable IPv6
echo "alias net-pf-10 off" >> /etc/modprobe.d/noipv6.conf
echo "options ipv6 disable=1" >> /etc/modprobe.d/noipv6.conf
sed -ci 's/NETWORKING_IPV6.*/NETWORKING_IPV6=no/' /etc/sysconfig/network
chkconfig ip6tables off
sed -ci 's/inet_protocols\ =\ all/inet_protocols\ =\ ipv4/g' /etc/postfix/main.cf

# Start post install kernel options update
/sbin/grubby --update-kernel=`/sbin/grubby --default-kernel` --args="noipv6 amd_iommu=on elevator=noop"
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
