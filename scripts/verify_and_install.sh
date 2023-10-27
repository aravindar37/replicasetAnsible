grep -q 'vm.zone_reclaim_mode' /etc/sysctl.conf || echo "vm.zone_reclaim_mode=0" | sudo tee --append /etc/sysctl.conf

grep -q 'vm.swappiness' /etc/sysctl.conf || echo "vm.swappiness=1" | sudo tee --append /etc/sysctl.conf

grep   "vm.swappiness=1" /etc/sysctl.conf || echo "Incorrect value for VM Swappiness"

for limit in fsize cpu as memlock
do
  grep "mongodb" /etc/security/limits.conf | grep -q $limit || echo -e "mongod     hard   $limit    unlimited\nmongod     soft    $limit   unlimited" | sudo tee --append /etc/security/limits.conf
done

for limit in nofile noproc
do
  grep "mongodb" /etc/security/limits.conf | grep -q $limit || echo -e "mongod     hard   $limit    64000\nmongod     soft    $limit   64000" | sudo tee --append /etc/security/limits.conf
done

SCRIPT=$(cat << 'ENDSCRIPT'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          disable-transparent-hugepages
# Required-Start:    $local_fs
# Required-Stop:
# X-Start-Before:    mongod mongodb-mms-automation-agent
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Disable Linux transparent huge pages
# Description:       Disable Linux transparent huge pages, to improve
#                    database performance.
### END INIT INFO

case $1 in
  start)
    if [ -d /sys/kernel/mm/transparent_hugepage ]; then
      thp_path=/sys/kernel/mm/transparent_hugepage
    elif [ -d /sys/kernel/mm/redhat_transparent_hugepage ]; then
      thp_path=/sys/kernel/mm/redhat_transparent_hugepage
    else
      return 0
    fi

    echo 'never' > ${thp_path}/enabled
    echo 'never' > ${thp_path}/defrag

    re='^[0-1]+$'
    if [[ $(cat ${thp_path}/khugepaged/defrag) =~ $re ]]
    then
      # RHEL 7
      echo 0  > ${thp_path}/khugepaged/defrag
    else
      # RHEL 6
      echo 'no' > ${thp_path}/khugepaged/defrag
    fi

    #Set Readahead for Data Disk
    blockdev --setra 8 /dev/xvdb
    unset re
    unset thp_path
    ;;
esac
ENDSCRIPT
)

echo "$SCRIPT" | sudo tee /etc/init.d/disable-transparent-hugepages

sudo chmod 755 /etc/init.d/disable-transparent-hugepages

sudo chkconfig --add disable-transparent-hugepages

sudo yum install make checkpolicy policycoreutils selinux-policy-devel

# copy the mongodb-selinux policy file prior to running this
sudo make install

cat << 'ENDOFDOC' | sudo tee /etc/yum.repos.d/mongodb-org-7.0.repo
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.com/yum/redhat/9/mongodb-org/7.0/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
ENDOFDOC

sudo yum install -y mongodb-org-7.0.2 mongodb-org-database-7.0.2 mongodb-org-server-7.0.2 mongodb-mongosh-7.0.2 mongodb-org-mongos-7.0.2 mongodb-org-tools-7.0.2

sudo mkdir /data/db
sudo chown mongod:mongod /data/db
sudo mkdir /data/logs
sudo chown mongod:mongod /data/logs

cat << 'ENDCONF' | sudo tee /etc/mongod.conf
# mongod.conf

# for documentation of all options, see:
#   http://docs.mongodb.org/manual/reference/configuration-options/

# where to write logging data.
systemLog:
  destination: file
  logAppend: true
  path: /data/logs/mongod.log

# Where and how to store data.
storage:
  dbPath: /data/db

# how the process runs
processManagement:
  fork: true  # fork and run in background
  pidFilePath: /var/run/mongodb/mongod.pid  # location of pidfile
  timeZoneInfo: /usr/share/zoneinfo

# network interfaces
net:
  port: 27017
  bindIpAll: true

security:
  authorization: enabled
replication:
  replSetName: AravindAsharamachandranRS
ENDCONF

sudo systemctl start mongod

sudo yum install mongodb-mongosh

mongosh --eval "rs.initiate()"

sudo systemctl enable mongod.service
