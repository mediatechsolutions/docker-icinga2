# docker-icinga2

## why does this exist?
existing icinga2 docker images normally merge icinga2, icingaweb2, mysql into a single image. The goal for this image is to split this up, so you can:
docker run --name icinga2-mariadb -e MYSQL_ROOT_PASSWORD secret mariadb
docker run --name icinga2 --link icinga2-mariadb:mysql rbicker/icinga2
docker run --name icingaweb2 --link icinga2-mariadb:mysql rbicker/icinga2

## what works?
not mutch yet, updates following soon
