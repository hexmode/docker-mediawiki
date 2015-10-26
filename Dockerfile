#*********************************************************************
#
# Copyright (c) 2015 BITPlan GmbH
#
# see LICENSE
#
# Dockerfile to build MediaWiki server
# Based on ubuntu
#
#*********************************************************************

# Ubuntu image
FROM ubuntu:14.04

#
# Maintained by Mark A. Hershberger / NicheWork LLC http://hexmode.com
# based on work by Wolfgang Fahl / BITPlan GmbH http://www.bitplan.com
#
MAINTAINER Mark A. Hershberger mah@nichework.com

#*********************************************************************
# Settings
#*********************************************************************

# Latest MediaWiki
ENV MEDIAWIKI_VERSION 1.25
ENV MEDIAWIKI mediawiki-1.25.3

#*********************************************************************
# Install Linux Apache MySQL PHP (LAMP)
#*********************************************************************

# see https://www.mediawiki.org/wiki/Manual:Running_MediaWiki_on_Ubuntu
RUN apt-get update -y

RUN \
  apt-get install -y \
	apache2 \
	curl \
	git \
	libapache2-mod-php5 \
	mysql-server \
	php5 \
	php5-cli \
	php5-gd \
	php5-mysql \
	php5-apcu \
	php5-intl \
        uuid-runtime


# see https://www.mediawiki.org/wiki/Manual:Installing_MediaWiki
RUN cd /var/www/html/ && \
  curl -O https://releases.wikimedia.org/mediawiki/$MEDIAWIKI_VERSION/$MEDIAWIKI.tar.gz && \
	tar -xzvf $MEDIAWIKI.tar.gz && \
	rm *.tar.gz

# Activea Apache PHP5 module
RUN a2enmod php5

COPY ./mediawiki-setup.sh /

RUN sh /mediawiki-setup.sh


#*********************************************************************
#* Expose relevant ports
#*********************************************************************
# http
EXPOSE 80
# https
EXPOSE 443
# mysql
EXPOSE 3306

cmd ["/usr/sbin/apache2", "-D",  "FOREGROUND"]
