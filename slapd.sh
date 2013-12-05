#!/bin/bash
### BEGIN INIT INFO
# Short-Description: OpenLDAP standalone server (Lightweight Directory Access Protocol) 
# Script instalation OpenLDAP
# Maintener: francois.trachez@enova.mx
# Version: 0.4 - 2013/12/04
#	Integracion update-rc.d slapd defaults & update-rc.d slapd remove
# Version: 0.3 - 2013/11/21
#	Integracion slapd.init y slapd.default en el slapd.sh
# Version: 0.2 - 2013/11/20
#	{Up|down}grade: automatizar el up|downgrade sin nombre paquete fijo
# Version: 0.1 - 2013/11/07
#	Initial script
### END INIT INFO

VERSION_INS=2.4.38
VERSION_SUP=`dpkg -l|grep openldap | awk -F '.' '{print $3+1}'|cut -d - -f1`
VERSION_INF=`dpkg -l|grep openldap | awk -F '.' '{print $3-1}'|cut -d - -f1`

#### Install OpenLDAP ####
install_ldap() {
if [ -z "`dpkg -l | grep openldap`" ]; then

# Update softwares
aptitude update
aptitude -y dist-upgrade

# Creation user openldap
if [ -z "`getent group openldap`" ]; then
        addgroup --quiet --system openldap
fi
if [ -z "`getent passwd openldap`" ]; then
        echo -n "  Creating new user openldap... " >&2
        adduser --quiet --system --home /var/lib/ldap --shell /bin/false \
                --ingroup openldap --disabled-password --disabled-login \
                --gecos "OpenLDAP Server Account" openldap
        echo "done." >&2
fi

# Creation directories openldap-data & run
if [ ! -d /var/lib/ldap/openldap-data ]; then
        mkdir -p -m 0700 /var/lib/ldap/openldap-data
        chown -R openldap:openldap /var/lib/ldap/openldap-data
fi
if [ ! -d /var/lib/ldap/run ]; then
        mkdir -p -m 0750 /var/lib/ldap/run
        chown -R openldap:openldap /var/lib/ldap/run
fi

# integrate the lib path
if [ -z "`ldconfig | grep -r /usr/local/ldap`" ]; then
        echo "/usr/local/ldap" > /etc/ld.so.conf.d/ldap.conf
        ldconfig
        echo "done." >&2
fi

# integrate the exec binaries path
if [ ! -d /etc/profile.d/slapd.sh ]; then
	echo "export PATH=$PATH:/usr/local/ldap/bin/:/usr/local/ldap/sbin/" >> /etc/profile.d/slapd.sh
	chmod +x /etc/profile.d/slapd.sh
	echo "done." >&2
fi
# installation dependances of packages
aptitude -y install gcc make libtool libperl-dev libdb5.1-dev libssl-dev libsasl2-dev

# execution .deb
dpkg -i ./openldap_$VERSION_INS-1_amd64.deb

# Creation directory slapd.d
if [ ! -d /usr/local/ldap/etc/openldap/slapd.d ]; then
        mkdir -p -m 0700 /usr/local/ldap/etc/openldap/slapd.d
        chown -R openldap:openldap /usr/local/ldap/etc/openldap/slapd.d
fi

# copy slapd.init file to init.d (service)
touch /etc/init.d/slapd
cat > /etc/init.d/slapd << "EOF"
#!/bin/sh
### BEGIN INIT INFO
# Provides:          slapd
# Required-Start:    $remote_fs $network $syslog
# Required-Stop:     $remote_fs $network $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: OpenLDAP standalone server (Lightweight Directory Access Protocol)
### END INIT INFO

# Specify path variable
PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/ldap/libexec:/usr/local/ldap/bin:/usr/local/ldap/sbin/

. /lib/lsb/init-functions

# Kill me on all errors
set -e

# Set the paths to slapd as a variable so that someone who really
# wants to can override the path in /etc/default/slapd.
SLAPD=/usr/local/ldap/libexec/slapd

# Stop processing if slapd is not there
[ -x $SLAPD ] || exit 0

# debconf may have this file descriptor open and it makes things work a bit
# more reliably if we redirect it as a matter of course.  db_stop will take
# care of this, but this won't hurt.
exec 3>/dev/null

# Source the init script configuration
if [ -f "/etc/default/slapd" ]; then
	. /etc/default/slapd
fi

# Load the default location of the slapd config file
if [ -z "$SLAPD_CONF" ]; then
	if [ -e /usr/local/ldap/etc/openldap/slapd.d ]; then
		SLAPD_CONF=/usr/local/ldap/etc/openldap/slapd.d
	else
		SLAPD_CONF=/usr/local/ldap/etc/openldap/slapd.conf
	fi
fi

# Stop processing if the config file is not there
if [ ! -r "$SLAPD_CONF" ]; then
  log_warning_msg "No configuration file was found for slapd at $SLAPD_CONF."
  # if there is no config at all, we should assume slapd is not running
  # and exit 0 on stop so that unconfigured packages can be removed.
  [ "x$1" = xstop ] && exit 0 || exit 1
fi

# extend options depending on config type
if [ -f "$SLAPD_CONF" ]; then
	SLAPD_OPTIONS="-f $SLAPD_CONF $SLAPD_OPTIONS"
elif [ -d "$SLAPD_CONF" ] ; then
	SLAPD_OPTIONS="-F $SLAPD_CONF $SLAPD_OPTIONS"
fi

# Find out the name of slapd's pid file
if [ -z "$SLAPD_PIDFILE" ]; then
	# If using old one-file configuration scheme
	if [ -f "$SLAPD_CONF" ] ; then
		SLAPD_PIDFILE=`sed -ne 's/^pidfile[[:space:]]\+\(.\+\)/\1/p' \
			"$SLAPD_CONF"`
	# Else, if using new directory configuration scheme
	elif [ -d "$SLAPD_CONF" ] ; then
		SLAPD_PIDFILE=`sed -ne \
			's/^olcPidFile:[[:space:]]\+\(.\+\)[[:space:]]*/\1/p' \
			"$SLAPD_CONF"/'cn=config.ldif'`
	fi
fi

# XXX: Breaks upgrading if there is no pidfile (invoke-rc.d stop will fail)
# -- Torsten
if [ -z "$SLAPD_PIDFILE" ]; then
	log_failure_msg "The pidfile for slapd has not been specified"
	exit 1
fi

# Make sure the pidfile directory exists with correct permissions
piddir=`dirname "$SLAPD_PIDFILE"`
if [ ! -d "$piddir" ]; then
	mkdir -p "$piddir"
	[ -z "$SLAPD_USER" ] || chown -R "$SLAPD_USER" "$piddir"
	[ -z "$SLAPD_GROUP" ] || chgrp -R "$SLAPD_GROUP" "$piddir"
fi

# Pass the user and group to run under to slapd
if [ "$SLAPD_USER" ]; then
	SLAPD_OPTIONS="-u $SLAPD_USER $SLAPD_OPTIONS"
fi

if [ "$SLAPD_GROUP" ]; then
	SLAPD_OPTIONS="-g $SLAPD_GROUP $SLAPD_OPTIONS"
fi

# Check whether we were configured to not start the services.
check_for_no_start() {
	if [ -n "$SLAPD_NO_START" ]; then
		echo 'Not starting slapd: SLAPD_NO_START set in /etc/default/slapd' >&2
		exit 0
	fi
	if [ -n "$SLAPD_SENTINEL_FILE" ] && [ -e "$SLAPD_SENTINEL_FILE" ]; then
		echo "Not starting slapd: $SLAPD_SENTINEL_FILE exists" >&2
		exit 0
	fi
}

# Tell the user that something went wrong and give some hints for
# resolving the problem.
report_failure() {
	log_end_msg 1
	if [ -n "$reason" ]; then
		log_failure_msg "$reason"
	else
		log_failure_msg "The operation failed but no output was produced."

		if [ -n "$SLAPD_OPTIONS" -o \
		     -n "$SLAPD_SERVICES" ]; then
			if [ -z "$SLAPD_SERVICES" ]; then
				if [ -n "$SLAPD_OPTIONS" ]; then
					log_failure_msg "Command line used: slapd $SLAPD_OPTIONS"
				fi
			else
				log_failure_msg "Command line used: slapd -h '$SLAPD_SERVICES' $SLAPD_OPTIONS"
			fi
		fi
	fi
}

# Start the slapd daemon and capture the error message if any to 
# $reason.
start_slapd() {
	if [ -z "$SLAPD_SERVICES" ]; then
		reason="`start-stop-daemon --start --quiet --oknodo \
			--pidfile "$SLAPD_PIDFILE" \
			--exec $SLAPD -- $SLAPD_OPTIONS 2>&1`"
	else
		reason="`start-stop-daemon --start --quiet --oknodo \
			--pidfile "$SLAPD_PIDFILE" \
			--exec $SLAPD -- -h "$SLAPD_SERVICES" $SLAPD_OPTIONS 2>&1`"
	fi

	# Backward compatibility with OpenLDAP 2.1 client libraries.
	if [ ! -h /var/run/ldapi ] && [ ! -e /var/run/ldapi ] ; then
		ln -s slapd/ldapi /var/run/ldapi
	fi
}

# Stop the slapd daemon and capture the error message (if any) to
# $reason.
stop_slapd() {
	reason="`start-stop-daemon --stop --quiet --oknodo --retry TERM/10 \
		--pidfile "$SLAPD_PIDFILE" \
		--exec $SLAPD 2>&1`"
}

# Start the OpenLDAP daemons
start_ldap() {
	trap 'report_failure' 0
	log_daemon_msg "Starting OpenLDAP" "slapd"
	start_slapd
	trap "-" 0
	log_end_msg 0
}

# Stop the OpenLDAP daemons
stop_ldap() {
	trap 'report_failure' 0
	log_daemon_msg "Stopping OpenLDAP" "slapd"
	stop_slapd
	trap "-" 0
	log_end_msg 0
}

case "$1" in
  start)
	check_for_no_start
  	start_ldap ;;
  stop)
  	stop_ldap ;;
  restart|force-reload)
	check_for_no_start
  	stop_ldap
	start_ldap
	;;
  status)
	status_of_proc -p $SLAPD_PIDFILE $SLAPD slapd
	;;
  *)
  	echo "Usage: $0 {start|stop|restart|force-reload|status}"
	exit 1
	;;
esac
EOF

chmod 0700 /etc/init.d/slapd

# creation slapd.default file to /etc/default/
touch /etc/default/slapd
cat > /etc/default/slapd << "EOF"
# Default location of the slapd.conf file or slapd.d cn=config directory. If
# empty, use the compiled-in default (/etc/ldap/slapd.d with a fallback to
# /etc/ldap/slapd.conf).
SLAPD_CONF=

# System account to run the slapd server under. If empty the server
# will run as root.
SLAPD_USER="openldap"

# System group to run the slapd server under. If empty the server will
# run in the primary group of its user.
SLAPD_GROUP="openldap"

# Path to the pid file of the slapd server. If not set the init.d script
# will try to figure it out from $SLAPD_CONF (/etc/ldap/slapd.d by
# default)
SLAPD_PIDFILE=

# slapd normally serves ldap only on all TCP-ports 389. slapd can also
# service requests on TCP-port 636 (ldaps) and requests via unix
# sockets.
# Example usage:
# SLAPD_SERVICES="ldap://127.0.0.1:389/ ldaps:/// ldapi:///"
SLAPD_SERVICES="ldap:/// ldapi:///"

# If SLAPD_NO_START is set, the init script will not start or restart
# slapd (but stop will still work).  Uncomment this if you are
# starting slapd via some other means or if you don't want slapd normally
# started at boot.
#SLAPD_NO_START=1

# If SLAPD_SENTINEL_FILE is set to path to a file and that file exists,
# the init script will not start or restart slapd (but stop will still
# work).  Use this for temporarily disabling startup of slapd (when doing
# maintenance, for example, or through a configuration management system)
# when you don't want to edit a configuration file.
SLAPD_SENTINEL_FILE=/usr/local/etc/openldap/noslapd

# For Kerberos authentication (via SASL), slapd by default uses the system
# keytab file (/etc/krb5.keytab).  To use a different keytab file,
# uncomment this line and change the path.
#export KRB5_KTNAME=/etc/krb5.keytab

# Additional options to pass to slapd
SLAPD_OPTIONS=""

EOF

else
	echo "Ya el servicio slapd esta instalado" >&2

fi

# add service with update-rc.d
update-rc.d slapd defaults

}


#### Delete OpenLDAP ####
delete_ldap() {
if [ -n "`dpkg -l | grep openldap`" ]; then
# stop slapd daemon
UIDLDAP=`pgrep slapd`
kill -9 $UIDLDAP

# delete config repository
echo -n "Removing slapd configuration... "
rm -Rf /usr/local/ldap/*
rm -Rf /usr/local/ldap

# delete db repository & PID repository
echo -n "Purging OpenLDAP database... "
rm -Rf /var/lib/ldap/openldap-data
rm -Rf /var/lib/ldap/run

# delete .deb package
dpkg -r openldap

# delete dependences
aptitude -y remove make libtool libperl-dev libdb5.1-dev libssl-dev libsasl2-dev

# delete libraries path
rm -Rf /etc/ld.so.conf.d/ldap.conf
ldconfig

# delete the exec binaries path
rm /etc/profile.d/slapd.sh

# delete openldap account
userdel -r openldap
groupdel -r openldap

# delete /etc/default/slapd and /etc/init.d/slapd
rm -Rf /etc/default/slapd
rm -Rf /etc/init.d/slapd

else
	echo "El servicio slapd no esta instalado" >&2
fi

# delete service with update-rc.d
update-rc.d slapd remove

}

#### Status OpenLDAP ####
status_install_ldap() {
if [ -n "`dpkg -l | grep openldap`" ]; then
	echo "El servicio slapd esta instalado" >&2
	echo "version `dpkg -l | grep openldap | awk '{print $3}'`" >&2
else
	echo "El servicio slapd no esta instalado" >&2
fi
}

#### Upgrade OpenLDAP ####
upgrade_ldap() {
if [ ! -f ./openldap_2.4.$VERSION_SUP-1_amd64.deb ]; then
	echo "El paquete openldap_2.4.$VERSION_SUP-1_amd64.deb no existe" >&2
else

# stop slapd daemon
UIDLDAP=`pgrep slapd`
if [ $UIDLDAP > 0 ];
	then
	while [ $UIDLDAP > 0 ]; do
	service slapd stop
	UIDLDAP=`pgrep slapd`
	done
fi

# execution .deb
dpkg -i ./openldap_2.4.$VERSION_SUP-1_amd64.deb

# re-execution of the slapd service
service slapd start

# version instaled
echo "version `dpkg -l | grep openldap | awk '{print $3}'` instalada" >&2

fi
}

#### Downgrade OpenLDAP ####
downgrade_ldap() {
if [ ! -f ./openldap_2.4.$VERSION_INF-1_amd64.deb ]; then
	echo "El paquete openldap_2.4.$VERSION_INF-1_amd64.deb no existe" >&2
else

# stop slapd daemon
UIDLDAP=`pgrep slapd`
if [ $UIDLDAP > 0 ];
	then
	while [ $UIDLDAP > 0 ]; do
	service slapd stop
	UIDLDAP=`pgrep slapd`
	done
fi

# execution .deb
dpkg -i ./openldap_2.4.$VERSION_INF-1_amd64.deb

# re-execution of the slapd service
service slapd start

# version instaled
echo "version `dpkg -l | grep openldap | awk '{print $3}'` instalada" >&2

fi
}

#### Cases ####
case "$1" in
  install)
        install_ldap ;;
  delete)
        delete_ldap ;;
  reinstall)
        delete_ldap
        install_ldap
        ;;
  status)
        status_install_ldap
        ;;
  upgrade)
	upgrade_ldap
	;;
  downgrade)
	downgrade_ldap
	;;
  *)
        echo "Usage: $0 {install|delete|reinstall|status|upgrade|downgrade}"
        exit 1
        ;;
esac
