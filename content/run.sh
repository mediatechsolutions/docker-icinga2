#!/bin/bash

# mysql variables
#MYSQL_HOST="${MYSQL_PORT_3306_TCP_ADDR}"
MYSQL_HOST="${MYSQL_HOST:-mysql}"
MYSQL_ROOT_PASSWORD=${MYSQL_ENV_MYSQL_ROOT_PASSWORD:-${MYSQL_ROOT_PASSWORD}}
MYSQL_CREATE_DB_CMD="CREATE DATABASE ${MYSQL_ICINGA_DB}; \
        GRANT SELECT, INSERT, UPDATE, DELETE, DROP, CREATE VIEW, INDEX, EXECUTE ON ${MYSQL_ICINGA_DB}.* TO '${MYSQL_ICINGA_USER}'@'%' IDENTIFIED BY '${MYSQL_ICINGA_PASSWORD}';"

# check linked mysql container
while ! ping -c1 -w3 $MYSQL_HOST &>/dev/null; do
  echo "ping to ${MYSQL_HOST} failed - waiting for mysql container"
  sleep 1
done
while ! mysqlshow -h ${MYSQL_HOST} --u root -p${MYSQL_ROOT_PASSWORD} ; do
  echo "Mysql does not answer yet"
  sleep 1
done

#start sshd for command transfer
/usr/sbin/sshd

# icinga2 features
echo "enabling icinga2 features"
# enable ido-mysql
if [[ -L /etc/icinga2/features-enabled/ido-mysql.conf ]]; then
  echo "symlink for /etc/icinga2/features-enabled/ido-mysql.conf already exists";
  else
    ln -s /etc/icinga2/features-available/ido-mysql.conf /etc/icinga2/features-enabled/ido-mysql.conf;
	# adjusting configuration
	sed -i "s/user.*/user = \"${MYSQL_ICINGA_USER}\",/g" /etc/icinga2/features-available/ido-mysql.conf
	sed -i "s/password.*/password = \"${MYSQL_ICINGA_PASSWORD}\",/g" /etc/icinga2/features-available/ido-mysql.conf
	sed -i "s/host.*/host = \"${MYSQL_HOST}\",/g" /etc/icinga2/features-available/ido-mysql.conf
	sed -i "s/database.*/database = \"${MYSQL_ICINGA_DB}\",/g" /etc/icinga2/features-available/ido-mysql.conf
	echo "enabled ido-mysql"
fi


# enable command
if [[ -L /etc/icinga2/features-enabled/command.conf ]]; then
  echo "command feature already enabled";
  else
    ln -s /etc/icinga2/features-available/command.conf /etc/icinga2/features-enabled/command.conf;
fi


# enable api
if [[ ! -L /etc/icinga2/features-enabled/api.conf ]]; then
  icinga2 api setup
  sed -i "s/\/\/const NodeName.*/const NodeName = \"${HOSTNAME}\"/" /etc/icinga2/constants.conf
  SALT=`cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 16 | head -n 1`
  sed -i "s/const TicketSalt.*/const TicketSalt = \"${SALT}\"/" /etc/icinga2/constants.conf
  cat <<EOF >> /etc/icinga2/conf.d/api-users.conf

object ApiUser  "${API_USER}" {
  password =  "${API_PASSWORD}"
  permissions = [ "*" ]
}
EOF
  #ln -s /etc/icinga2/features-available/api.conf /etc/icinga2/features-enabled/api.conf;

  echo "enabled api"
  else
    echo "symlink for /etc/icinga2/features-enabled/api.conf already exists";
fi

# check if icinga database exists
if mysqlshow -h ${MYSQL_HOST} --u root -p${MYSQL_ROOT_PASSWORD} ${MYSQL_ICINGA_DB}  &>/dev/null; then
  echo "found icinga2 mysql database in linked mysql container"
  else
    echo "mysql database ${MYSQL_DB_NAME} not found"
    # create database
    if mysql -h ${MYSQL_HOST} -u root -p${MYSQL_ROOT_PASSWORD} -e "${MYSQL_CREATE_DB_CMD}"; then
      echo "created database ${MYSQL_DB_NAME}"
	  if mysql -h ${MYSQL_HOST} -u root -p${MYSQL_ROOT_PASSWORD} ${MYSQL_ICINGA_DB} < /usr/share/icinga2-ido-mysql/schema/mysql.sql; then
	    echo "created icinga2 mysql database schema"
		else
		  >&2 echo "error creating icinga2 database schema"
		  exit 1
	  fi
      else
        >&2 echo "error creating database ${MYSQL_DB_NAME}"
		exit 1
    fi
fi

# preparing /var/run (icinga2 cannot start in foreground otherwise)
if [[ ! -e /var/run/icinga2/cmd ]]; then
  echo "creating /var/run/icinga2 directory"
  mkdir -p /var/run/icinga2/cmd
  chown -R nagios:nagios /var/run/icinga2
fi

# start icinga2 in foreground
echo "starting icinga2..."
/usr/sbin/icinga2 daemon
