install
text
skipx
url --url http://mirror.cogentco.com/pub/linux/centos/6/os/x86_64/
repo --name=updates	--baseurl=http://mirror.cogentco.com/pub/linux/centos/6/updates/x86_64/
repo --name=rpmfusion	--baseurl=http://pkgs.repoforge.org/rpmforge-release/
# repo --name=epel	--baseurl=http://download.fedoraproject.org/pub/epel/6/x86_64/
lang en_US.UTF-8
keyboard us
rootpw --iscrypted $1$ZBPaRszr$/hHqikLgPn4I/T/n2zdy41
user --name=corey --password=$1$ToCwIHYP$ozAGkOzRhbvlJHiabmP5i/ --iscrypted
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

###### FUNCTION SECTION ######

function configHypervisor()
{
  yum install kvm libvirt -y
	service libvirtd restart
	groupadd libvirt
	usermod -a -G kvm corey
	usermod -a -G libvirt corey
	virsh iface-bridge eth0 br0
	cat << EOF >> /etc/sysconfig/network-scripts/ifcfg-br0
	
	EOF
	service network restart
	echo "todo: add iptables rule for bridge"
	cat << EOF >> /etc/sysctl.conf

net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-arptables = 0
EOF
	sysctl -p /etc/sysctl.conf
	service libvirtd reload

	echo "configure lvm partitions for guest disk"
	GUESTSIZE=12GB
	for GUEST in hawkeye sanders nile ; do
		lvcreate --size ${GUESTSIZE} -n lv_vm_${GUEST} vg_fry 
		mke2fs -j -t ext4 /dev/vg_fry/lv_vm_${GUEST}
	done
	setsebool -P virt_use_sysfs 1

	echo "client instructions with virt manager"
	echo "sudo yum install virt-manager -y"
	echo "sudo virt-install --connect qemu:///system -n <GUESTNAME> -r 1024 --vcpus=2 --disk path=/dev/vg_fry/lv_vm_<GUESTNAME>,size=12 --spice --noautoconsole --os-type linux --os-variant centos6 --network=bridge:br0 --hvm --pxe"
	echo "virsh attach-device <GUESTNAME> file.xml (see https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Virtualization_Host_Configuration_and_Guest_Installation_Guide/chap-Virtualization_Host_Configuration_and_Guest_Installation_Guide-PCI_Device_Config.html)"
}

configGuest()
{
	yum install rsyslog stunnel -y
	configAll
	configLdap

	echo "configure services for secure remote logging"
	cat << stunnel_EOF > /etc/stunnel/stunnel.conf
; Client side configuration
client=yes
[ssyslog]
accept = 127.0.0.1:61514
connect = sanders.kinnick:60514
stunnel_EOF
	cat << rsyslog_EOF >> /etc/rsyslog.conf

# log everything remotely through stunnel
*.*                                                     @@127.0.0.1:61514
rsyslog_EOF

	echo "enable the stunnel service"
	groupadd -g 109 stunnel
	useradd -u 109 -g 109 -M -N -s /sbin/nlogin stunnel
	chmod 755 /etc/rc.d/init.d/stunnel
	chkconfig --add stunnel; chkconfig stunnel on
}

configAll()
{
	echo "configure sudo"
	cat << EOF >> /etc/sudoers

corey   ALL=(ALL)       NOPASSWD: ALL
EOF

	echo "disable root login via ssh"
	sed -i s/^\#PermitRootLogin.*/PermitRootLogin\ no/ /etc/ssh/sshd_config

	echo "we'd rather not use /opt"
	(umask 222 ; cat << EOF > /opt/README
Please install local applications under /usr/local instead of /opt
EOF
)

	echo "add entry for the local machine to the hosts file"
	echo "$IP_ADDRESS       $HOSTNAME $SHORTNAME" >> /etc/hosts

	echo "repair the localhost entry in the hosts file"
	sed -ci s/^127\.0\.0\.1.*/127\.0\.0\.1\ \ \ localhost.localdomain\ localhost/ /etc/hosts

	echo "disable IPv6"
	echo "alias net-pf-10 off" >> /etc/modprobe.d/noipv6.conf
	echo "options ipv6 disable=1" >> /etc/modprobe.d/noipv6.conf
	sed -ci 's/NETWORKING_IPV6.*/NETWORKING_IPV6=no/' /etc/sysconfig/network
	chkconfig ip6tables off
	sed -ci 's/inet_protocols\ =\ all/inet_protocols\ =\ ipv4/g' /etc/postfix/main.cf
}

configLdap()
{
	yum install krb5-workstation pam_krb5 openldap-clients nss-pam-ldapd sssd -y

	echo "configure system authentication and authorization for Active Directory"
	authconfig  --useshadow  --enablemd5  --enablecache --enablekrb5 --krb5realm=KINNICK --enablekrb5kdcdns --enablekrb5realmdns --enablemkhomedir --enablelocauthorize --enableldap --ldapserver=ldap.kinnick --ldapbasedn="dc=kinnick" --disablesmartcard --disablefingerprint --update

	echo "set proper directory permissions for home directory creation in /etc/pam.d/system-auth"
	sed -ci '/pam_mkhomedir.so/s/$/\ umask\=077/' /etc/pam.d/system-auth-ac
	
	echo "TODO: configure sssd"
}

###### END FUNCTION SECTION ######


# If this is a VM, install virtio paravirtualization tools from the configured repo
# http://wiki.libvirt.org/page/Virtio




# Start post install kernel options update
/sbin/grubby --update-kernel=`/sbin/grubby --default-kernel` --args="noipv6 amd_iommu=on"
if ( grep -q '6\.' /etc/redhat-release ) ; then
	/usr/sbin/plymouth-set-default-theme details
	/usr/libexec/plymouth/plymouth-update-initrd
fi
# End post install kernel options update

# guest server customizations
case `echo $(hostname -s)` in
	hawkeye)
		echo "detected nfs/samba server with bulk storage pci passthrough"
		configureGuest
		;;
	sanders)
		echo "detected centralized rsyslog and reporting server"
		echo "todo: rsyslog and reporting server config"
		configureGuest
		;;
	nile)
		echo "detected open ldap server"
		echo "todo: openldap server config"
		configureGuest
		;;
	dwight)
		echo "detected home theater pc (htpc) and dlna server"
		echo "TODO: dlna server config; nfs mounts to media"
		configureGuest
	fry)
		echo "detected hypervisor install"
		configureHypervisor
		;;
esac

# echo "must schedule yum update as some problems can occur if doing too soon at provision time"
# service atd start
# echo "/usr/bin/yum update -y; /sbin/init 6" | at now + 4 minutes
yum update -y

# Close out %post logging
) 2>&1 | /usr/bin/tee /root/ks-post.log
chvt 1

%end
