#!/bin/sh -e

. /etc/apache2/envvars
/usr/sbin/apache2ctl start
tail -f /var/log/apache2/error.log

