#!/bin/bash
#
# Copyright (c) 2015 BITPlan GmbH
#
# see LICENSE
#
# WF 2015-10-18
#
# Mediawiki docker image entrypoint script
#
# see
# https://www.mediawiki.org/wiki/Manual:Installing_MediaWiki
#
set -e


#
# generate a random password
#
random_password() {
    date +%N | sha256sum | base64 | head -c 16 ; echo
}

#
# get the database environment
#  params:
#     1: l_settings - the Localsettings to get the db info from
#
#
getdbenv() {
    local l_settings="$1"

    # get database parameters from local settings
    dbserver=`egrep '^.wgDBserver' $l_settings | cut -d'"' -f2`
    dbname=`egrep '^.wgDBname'     $l_settings | cut -d'"' -f2`
    dbuser=`egrep '^.wgDBuser'     $l_settings | cut -d'"' -f2`
    dbpass=`egrep '^.wgDBpassword' $l_settings | cut -d'"' -f2`
}

#
# do an sql command
#  params:
#     1: l_settings - the Localsettings to get the db info from
#
dosql() {
    # get parameters
    local l_settings="$1"
    # get database parameters from local settings
    getdbenv "$l_settings"
    # uncomment for debugging mysql statement
    #echo mysql --host="$dbserver" --user="$dbuser" --password="$dbpass" "$dbname"
    mysql --host="$dbserver" "$dbname" 2>&1
}

#
# prepare mysql
#
prepare_mysql() {
    service mysql start
    MYSQL_PASSWD=`random_password`
    echo "setting MySQL password to random password $MYSQL_PASSWD"
    mysqladmin -u root password $MYSQL_PASSWD
    echo '[mysql]' > ~/.my.cnf
    echo 'user = root' >> ~/.my.cnf
    echo "password = $MYSQL_PASSWD" >> ~/.my.cnf
}

#
# check the Wiki Database defined in the  LocalSettings.php for the given site
#  params:
#   1: settings - the LocalSettings path e.g /var/www/html/mediawiki/LocalSettings.php
#
checkWikiDB() {
    # get parameters
    local l_settings="$1"
    echo "checking Wiki Database"

    # check mysql access
    l_pages=$(echo "select count(*) as pages from page" | dosql "$l_settings" || true)
    #
    # this will return a number of pages or a mysql ERROR
    #
    if [[ "$l_pages" != *"ERROR 1049"* ]]; then
        # if the db does not exist or access is otherwise denied:
        # ERROR 1045 (28000): Access denied for user '<user>'@'localhost' (using password: YES)
	if [[ "$l_pages" != *"ERROR 1045"* ]]; then
	    # if the db was just created:
	    #ERROR 1146 (42S02) at line 1: Table '<dbname>.page' doesn't exist
	    if [[ "$l_pages" != *"ERROR 1146"* ]]; then
	        # if everything was o.k.
	        if [[ "$l_pages" != *"pages"* ]]; then
	            # something unexpected
	            echo "*** $l_pages"
                    exit 1
	        else
	            # this is what we expect
	            echo "$l_pages"
	        fi
	    else
	        # db just created - fill it
	        echo "$dbname seems to be just created and empty - shall I initialize it with the backup from an empty mediawiki database? y/n"
	        read answer
	        case $answer in
	            y|Y|yes|Yes) initialize $l_settings;;
	            *) echo "ok - leaving things alone ...";;
	        esac
	    fi
	else
	    # something unexpected
	    echo "*** $l_pages"
	fi
    else
	getdbenv "$l_settings"
	echo  "$l_pages: database $dbname not created yet"
	echo "will create database $dbname now ..."
	echo "create database $dbname;" | mysql --host="$dbserver" --user="$dbuser" --password="$dbpass" 2>&1
	echo "grant all privileges on $dbname.* to $dbuser@'localhost' identified by '"$dbpass"';" | dosql "$l_settings"
    fi
}


#
# prepare mediawiki
#
#  params:
#   1: settings - the LocalSettings path e.g /var/www/html/mediawiki/LocalSettings.php
#
prepare_mediawiki() {
    local l_settings="$1"
    local l_hostname=`hostname`
    local l_secretkey=`uuidgen | md5sum | cut -f1 -d" "`
    local l_updatekey=`uuidgen | md5sum | cut -c 1-12`
    ln -s $mwpath $apachepath/mediawiki
    cat << EOF > $l_settings
<?php
# This file was automatically generated by the MediaWiki 1.25.3
# installer. If you make manual changes, please keep track in case you
# need to recreate them later.
#
# See includes/DefaultSettings.php for all configurable settings
# and their default values, but don't forget to make changes in _this_
# file, not there.
#
# Further documentation for configuration settings may be found at:
# https://www.mediawiki.org/wiki/Manual:Configuration_settings

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

## Uncomment this to disable output compression
# \$wgDisableOutputCompression = true;

\$wgSitename = "mediawiki@localhost";
\$wgMetaNamespace = "Mediawiki@localhost";

## The URL base path to the directory containing the wiki;
## defaults for all runtime URL paths are based off of this.
## For more information on customizing the URLs
## (like /w/index.php/Page_title to /wiki/Page_title) please see:
## https://www.mediawiki.org/wiki/Manual:Short_URL
\$wgScriptPath = "/mediawiki";
\$wgScriptExtension = ".php";

## The protocol and server name to use in fully-qualified URLs
\$wgServer = "http://$l_hostname";

## The relative URL path to the skins directory
\$wgStylePath = "\$wgScriptPath/skins";
\$wgResourceBasePath = \$wgScriptPath;

## The relative URL path to the logo.  Make sure you change this from the default,
## or else you'll overwrite your logo when you upgrade!
\$wgLogo = "\$wgResourceBasePath/resources/assets/wiki.png";

## UPO means: this is also a user preference option

\$wgEnableEmail = true
\$wgEnableUserEmail = true; # UPO

\$wgEmergencyContact = "apache@$l_hostname";
\$wgPasswordSender = "apache@$l_hostname";

\$wgEnotifUserTalk = false; # UPO
\$wgEnotifWatchlist = false; # UPO
\$wgEmailAuthentication = true;

## Database settings
\$wgDBtype = "mysql";
\$wgDBserver = "localhost";
\$wgDBname = "wiki";
\$wgDBuser = "root";
\$wgDBpassword = "$MYSQL_PASSWD";

# MySQL specific settings
\$wgDBprefix = "";

# MySQL table options to use during installation or update
\$wgDBTableOptions = "ENGINE=InnoDB, DEFAULT CHARSET=binary";

# Experimental charset support for MySQL 5.0.
\$wgDBmysql5 = false;

## Shared memory settings
\$wgMainCacheType = CACHE_NONE;
\$wgMemCachedServers = array();

## To enable image uploads, make sure the 'images' directory
## is writable, then set this to true:
\$wgEnableUploads = true;
#\$wgUseImageMagick = true;
#\$wgImageMagickConvertCommand = "/usr/bin/convert";

# InstantCommons allows wiki to use images from http://commons.wikimedia.org
\$wgUseInstantCommons = false;

## If you use ImageMagick (or any other shell command) on a
## Linux server, this will need to be set to the name of an
## available UTF-8 locale
\$wgShellLocale = "C.UTF-8";

## If you want to use image uploads under safe mode,
## create the directories images/archive, images/thumb and
## images/temp, and make them all writable. Then uncomment
## this, if it's not already uncommented:
#\$wgHashedUploadDirectory = false;

## Set \$wgCacheDirectory to a writable directory on the web server
## to make your wiki go slightly faster. The directory should not
## be publically accessible from the web.
#\$wgCacheDirectory = "$IP/cache";

# Site language code, should be one of the list in ./languages/Names.php
\$wgLanguageCode = "en";

\$wgSecretKey = "$l_secretkey";

# Site upgrade key. Must be set to a string (default provided) to turn on the
# web installer while LocalSettings.php is in place
\$wgUpgradeKey = "$l_upgradekey";

## For attaching licensing metadata to pages, and displaying an
## appropriate copyright notice / icon. GNU Free Documentation
## License and Creative Commons licenses are supported so far.
\$wgRightsPage = ""; # Set to the title of a wiki page that describes your license/copyright
\$wgRightsUrl = "";
\$wgRightsText = "";
\$wgRightsIcon = "";

# Path to the GNU diff3 utility. Used for conflict resolution.
\$wgDiff3 = "/usr/bin/diff3";

## Default skin: you can change the default skin. Use the internal symbolic
## names, ie 'vector', 'monobook':
\$wgDefaultSkin = "vector";

# Enabled skins.
# The following skins were automatically enabled:
wfLoadSkin( 'CologneBlue' );
wfLoadSkin( 'Modern' );
wfLoadSkin( 'MonoBook' );
wfLoadSkin( 'Vector' );

# The following permissions were set based on your choice in the installer
\$wgGroupPermissions['*']['createaccount'] = false;
\$wgGroupPermissions['*']['edit'] = false;
\$wgGroupPermissions['*']['read'] = false;

# Enabled Extensions.
wfEnableExtension( 'ParserFunctions' );
wfEnableExtension( 'SytaxHighlight_GeSHi' );
wfEnableExtension( 'WikiEditor' );
wfEnableExtension( 'PdfHandler' );

# End of automatically generated settings.
# Add more configuration options below.
EOF
}

#
# Start of Docker Entrypoint
#
echo "Preparing Mediawiki $MEDIAWIKI_VERSION docker image"

# set the Path to the Apache Document root
apachepath=/var/www/html

# set the Path to the Mediawiki installation (influenced by MEDIAWIKI ENV variable)
mwpath=$apachepath/$MEDIAWIKI

# MediaWiki LocalSettings.php path
localsettings_dist=$mwpath/LocalSettings.php.dist
localsettings_inst=$mwpath/LocalSettings.php.inst
localsettings=$mwpath/LocalSettings.php

# prepare mysql
prepare_mysql

# prepare the mediawiki
prepare_mediawiki $localsettings_dist

# create a random SYSOP passsword
SYSOP_PASSWD=`random_password`

# run the Mediawiki install script
php $mwpath/maintenance/install.php \
    --dbname "wiki" \
    --dbpass "$MYSQL_PASSWD" \
    --dbserver localhost \
    --dbtype mysql \
    --dbuser root \
    --email mediawiki@localhost \
    --installdbpass $dbpass \
    --installdbuser $dbuser \
    --pass $SYSOP_PASSWD \
    --scriptpath /mediawiki \
    Sysop

# make sure the Wiki Database exists
 checkWikiDB $localsettings_dist

# get the database environment variables
getdbenv $localsettings_dist

echo "Mediawiki has been installed with a single user"
echo "select user_name from user" | dosql $localsettings_dist

# enable the LocalSettings
# move the LocalSettings.php created by the installer above to the side
mv $localsettings $localsettings_inst
# use the one created by this script instead
mv $localsettings_dist $localsettings

echo "you can now login to MediaWiki with"
echo "User:Sysop"
echo "Password:$SYSOP_PASSWD"
# Execute docker run parameter
