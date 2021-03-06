#!/bin/bash

# Constants
APP_PATH="/usr/local/src/ngmicro"

GET_HTTPD_VERSION=$(httpd -v | grep "Server version")
GET_CENTOS_VERSION=$(rpm -q --qf "%{VERSION}" $(rpm -q --whatprovides redhat-release))


############################# HELPER FUCTIONS [start] #############################

function install_basics {

    echo "=== Let's upgrade our system first & install a few required packages ==="
    yum -y update
    yum -y upgrade
    yum -y install atop bash-completion bc cronie curl htop ifstat iftop iotop make nano openssl-devel pcre pcre-devel sudo tree unzip zip zlib-devel
    yum clean all
    echo ""
    echo ""

}

function install_nginx {

    # Disable Nginx from the EPEL repo
    if [ -f /etc/yum.repos.d/epel.repo ]; then
        if ! grep -q "^exclude=nginx\*" /etc/yum.repos.d/epel.repo ; then
            if grep -Fq "#exclude=nginx*" /etc/yum.repos.d/epel.repo; then
                sed -i "s/\#exclude=nginx\*/exclude=nginx\*/" /etc/yum.repos.d/epel.repo
            else
                sed -i "s/enabled=1/enabled=1\nexclude=nginx\*/" /etc/yum.repos.d/epel.repo
            fi
            yum -y remove nginx
            yum clean all
            yum -y update
        fi
    fi

    if [ ! -f /etc/yum.repos.d/nginx.repo ]; then
        touch /etc/yum.repos.d/nginx.repo
    fi

    # Allow switching from mainline to stable release
    if [[ ! $1 ]]; then
        if grep -iq "mainline" /etc/yum.repos.d/nginx.repo; then
            yum -y remove nginx
        fi
    fi

    # Setup Nginx repo
    if [[ $1 == 'mainline' ]]; then
        echo "=== Install Nginx (mainline) from nginx.org ==="
        cat > "/etc/yum.repos.d/nginx.repo" <<EOFM
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=0
enabled=1
EOFM
    else
        echo "=== Install Nginx (stable) from nginx.org ==="
        cat > "/etc/yum.repos.d/nginx.repo" <<EOFS
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=0
enabled=1
EOFS
    fi

    # Install Nginx
    yum -y install nginx

    # Copy Nginx config files
    if [ ! -d /etc/nginx/conf.d ]; then
        mkdir -p /etc/nginx/conf.d
    fi

    if [ -f /etc/nginx/custom_rules ]; then
        /bin/cp -f $APP_PATH/nginx/custom_rules /etc/nginx/custom_rules.dist
    else
        /bin/cp -f $APP_PATH/nginx/custom_rules /etc/nginx/
    fi

    if [ -f /etc/nginx/proxy_params_common ]; then
        /bin/cp -f /etc/nginx/proxy_params_common /etc/nginx/proxy_params_common.bak
    fi
    /bin/cp -f $APP_PATH/nginx/proxy_params_common /etc/nginx/

    if [ -f /etc/nginx/proxy_params_dynamic ]; then
        /bin/cp -f /etc/nginx/proxy_params_dynamic /etc/nginx/proxy_params_dynamic.bak
    fi
    /bin/cp -f $APP_PATH/nginx/proxy_params_dynamic /etc/nginx/

    if [ -f /etc/nginx/proxy_params_static ]; then
        /bin/cp -f /etc/nginx/proxy_params_static /etc/nginx/proxy_params_static.bak
    fi
    /bin/cp -f $APP_PATH/nginx/proxy_params_static /etc/nginx/

    if [ -f /etc/nginx/mime.types ]; then
        /bin/cp -f /etc/nginx/mime.types /etc/nginx/mime.types.bak
    fi
    /bin/cp -f $APP_PATH/nginx/mime.types /etc/nginx/

    if [ -f /etc/nginx/nginx.conf ]; then
        /bin/cp -f /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
    fi
    /bin/cp -f $APP_PATH/nginx/nginx.conf /etc/nginx/

    if [ -f /etc/nginx/conf.d/default.conf ]; then
        /bin/cp -f /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
    fi
    /bin/rm -f /etc/nginx/conf.d/*.conf
    /bin/cp -f $APP_PATH/nginx/conf.d/default.conf /etc/nginx/conf.d/

    /bin/cp -f $APP_PATH/nginx/common_https.conf /etc/nginx/

    if [ ! -d /etc/ssl/ngmicro ]; then
        mkdir -p /etc/ssl/ngmicro
    fi

    if [ ! -d /var/cache/nginx ]; then
        mkdir -p /var/cache/nginx
    fi

    if [ -f /sbin/chkconfig ]; then
        /sbin/chkconfig nginx on
    else
        systemctl enable nginx
    fi

    if [ -f /usr/lib/systemd/system/nginx.service ]; then
        sed -i 's/PrivateTmp=true/PrivateTmp=false/' /usr/lib/systemd/system/nginx.service
        systemctl daemon-reload
    fi

    if [ "$(pstree | grep 'nginx')" ]; then
        service nginx stop
    fi

    # Adjust log rotation to 7 days
    if [ -f /etc/logrotate.d/nginx ]; then
        sed -i 's:rotate .*:rotate 7:' /etc/logrotate.d/nginx 
    fi

    echo ""
    echo ""

}

function remove_nginx {

    echo "=== Removing Nginx... ==="
    if [ -f /sbin/chkconfig ]; then
        /sbin/chkconfig nginx off
    else
        systemctl disable nginx
    fi

    service nginx stop

    yum -y remove nginx
    /bin/rm -rf /etc/nginx/*
    /bin/rm -f /etc/yum.repos.d/nginx.repo
    /bin/rm -rf /etc/ssl/ngmicro/*

    # Enable Nginx from the EPEL repo
    if [ -f /etc/yum.repos.d/epel.repo ]; then
        sed -i "s/^exclude=nginx\*/#exclude=nginx\*/" /etc/yum.repos.d/epel.repo
    fi

    echo ""
    echo ""

}

function chkserv_nginx_on {
    if [ -f /etc/chkserv.d/httpd ]; then
        echo ""
        echo "=== Enable TailWatch chkservd driver for Nginx ==="

        sed -i 's:service\[httpd\]=80,:service[httpd]=8080,:' /etc/chkserv.d/httpd
        echo "nginx:1" >> /etc/chkserv.d/chkservd.conf
        if [ ! -f /etc/chkserv.d/nginx ]; then
            touch /etc/chkserv.d/nginx
        fi
        echo "service[nginx]=80,GET / HTTP/1.0,HTTP/1..,killall -TERM nginx;sleep 2;killall -9 nginx;service nginx stop;service nginx start" > /etc/chkserv.d/nginx
        /scripts/restartsrv apache_php_fpm
        /scripts/restartsrv_chkservd
        echo ""
        echo ""
    fi
}

function chkserv_nginx_off {
    if [ -f /etc/chkserv.d/httpd ]; then
        echo ""
        echo "=== Disable TailWatch chkservd driver for Nginx ==="

        sed -i 's:service\[httpd\]=8080,:service[httpd]=80,:' /etc/chkserv.d/httpd
        sed -i 's:^nginx\:1::' /etc/chkserv.d/chkservd.conf
        if [ -f /etc/chkserv.d/nginx ]; then
            /bin/rm -f /etc/chkserv.d/nginx
        fi
        /scripts/restartsrv apache_php_fpm
        /scripts/restartsrv_chkservd
        echo ""
        echo ""
    fi
}

############################# HELPER FUCTIONS [end] #############################



### Define actions ###
case $1 in
install)

    clear

    if [ ! -f /ngmicro.sh ]; then
        echo ""
        echo ""
        echo "***********************************************"
        echo ""
        echo " ngmicro NOTICE:"
        echo " You must place & execute ngmicro.sh"
        echo " from the root directory (/) of your server!"
        echo ""
        echo " --- Exiting ---"
        echo ""
        echo "***********************************************"
        echo ""
        echo ""
        exit 0
    fi

    echo "**************************************"
    echo "*        Installing ngmicro        *"
    echo "**************************************"

    echo ""
    echo ""

    chmod +x /ngmicro.sh

    if [[ $2 == 'local' ]]; then
        echo -e "\033[36m=== Performing local installation from $APP_PATH... ===\033[0m"
        cd /
    else
        # Set ngmicro src file path
        if [[ ! -d $APP_PATH ]]; then
            mkdir -p $APP_PATH
        fi

        # Get the files
        cd $APP_PATH
        wget --no-check-certificate -O ngmicro.zip https://github.com/LegacyServer/ngmicro/archive/master.zip
        unzip ngmicro.zip
        /bin/cp -rf $APP_PATH/ngmicro-master/* $APP_PATH/
        /bin/rm -rvf $APP_PATH/ngmicro-master/*
        /bin/rm -f $APP_PATH/ngmicro.zip
        cd /
    fi

    echo ""
    echo ""

    install_basics
    install_nginx $2

    if [ ! -f /etc/ssl/certs/dhparam.pem ]; then
        echo ""
        echo "=== Generating DHE ciphersuites (2048 bits)... ==="
        openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048
    fi

    echo ""
    echo "=== Restarting Apache & Nginx... ==="
    /scripts/restartsrv apache_php_fpm
    /scripts/restartsrv_httpd
    fuser -k 80/tcp
    fuser -k 8080/tcp
    fuser -k 443/tcp
    fuser -k 8443/tcp
    service nginx start

    chkserv_nginx_on

    service nginx restart

    if [ ! -f $APP_PATH/state.conf ]; then
        touch $APP_PATH/state.conf
    fi
    echo "on" > $APP_PATH/state.conf

    if [ -f $APP_PATH/ngmicro.sh ]; then
        chmod +x $APP_PATH/ngmicro.sh
        $APP_PATH/ngmicro.sh purgecache

        # Update the /ngmicro.sh file when updating Engiintron with "$ /ngmicro.sh install"
        /bin/cp -f $APP_PATH/ngmicro.sh /
        chmod +x /ngmicro.sh
    fi

    /scripts/restartsrv apache_php_fpm
    /scripts/restartsrv_httpd

    sleep 5

    service httpd restart
    service nginx restart

    echo ""
    echo "**************************************"
    echo "*       Installation Complete        *"
    echo "**************************************"
    echo ""
    echo ""
    ;;
remove)

    clear

    echo "**************************************"
    echo "*         Removing ngmicro         *"
    echo "**************************************"

    remove_nginx
    chkserv_nginx_off

    echo ""
    echo "=== Removing ngmicro files... ==="
    /bin/rm -rvf $APP_PATH

    echo ""
    echo "=== Restarting Apache... ==="
    /scripts/restartsrv apache_php_fpm
    /scripts/restartsrv_httpd

    echo ""
    echo "**************************************"
    echo "*          Removal Complete          *"
    echo "**************************************"
    echo ""
    echo ""
    ;;
	
	
enable)
    clear

    echo "**************************************"
    echo "*         Enabling ngmicro         *"
    echo "**************************************"

    if [ ! -f $APP_PATH/state.conf ]; then
        touch $APP_PATH/state.conf
    fi
    echo "on" > $APP_PATH/state.conf

    service nginx stop
    sed -i 's:listen 8080 default_server:listen 80 default_server:' /etc/nginx/conf.d/default.conf
    sed -i 's:listen [\:\:]\:8080 default_server:listen [\:\:]\:80 default_server:' /etc/nginx/conf.d/default.conf
    sed -i 's:deny all; #:# deny all; #:' /etc/nginx/conf.d/default.conf
    sed -i 's:\:80; # Apache Status Page:\:8080; # Apache Status Page:' /etc/nginx/conf.d/default.conf
    if [ -f /etc/nginx/conf.d/default_https.conf ]; then
        sed -i 's:listen 8443 ssl:listen 443 ssl:g' /etc/nginx/conf.d/default_https.conf
        sed -i 's:listen [\:\:]\:8443 ssl:listen [\:\:]\:443 ssl:g' /etc/nginx/conf.d/default_https.conf
        sed -i 's:deny all; #:# deny all; #:g' /etc/nginx/conf.d/default_https.conf
    fi
    sed -i 's:PROXY_TO_PORT 443:PROXY_TO_PORT 8443:' /etc/nginx/common_https.conf
    sed -i 's:PROXY_DOMAIN_OR_IP\:80:PROXY_DOMAIN_OR_IP\:8080:' /etc/nginx/proxy_params_common
    service nginx start

    /scripts/restartsrv apache_php_fpm
    /scripts/restartsrv_httpd
    service nginx restart
    chkserv_nginx_on

    echo ""
    echo "**************************************"
    echo "*         ngmicro Enabled          *"
    echo "**************************************"
    echo ""
    echo ""
    ;;
	
	
disable)
    clear

    echo "**************************************"
    echo "*        Disabling ngmicro         *"
    echo "**************************************"

    if [ ! -f $APP_PATH/state.conf ]; then
        touch $APP_PATH/state.conf
    fi
    echo "off" > $APP_PATH/state.conf

    service nginx stop
    sed -i 's:listen 80 default_server:listen 8080 default_server:' /etc/nginx/conf.d/default.conf
    sed -i 's:listen [\:\:]\:80 default_server:listen [\:\:]\:8080 default_server:' /etc/nginx/conf.d/default.conf
    sed -i 's:# deny all; #:deny all; #:' /etc/nginx/conf.d/default.conf
    sed -i 's:\:8080; # Apache Status Page:\:80; # Apache Status Page:' /etc/nginx/conf.d/default.conf
    if [ -f /etc/nginx/conf.d/default_https.conf ]; then
        sed -i 's:listen 443 ssl:listen 8443 ssl:g' /etc/nginx/conf.d/default_https.conf
        sed -i 's:listen [\:\:]\:443 ssl:listen [\:\:]\:8443 ssl:g' /etc/nginx/conf.d/default_https.conf
        sed -i 's:# deny all; #:deny all; #:g' /etc/nginx/conf.d/default_https.conf
    fi
    sed -i 's:PROXY_TO_PORT 8443:PROXY_TO_PORT 443:' /etc/nginx/common_https.conf
    sed -i 's:PROXY_DOMAIN_OR_IP\:8080:PROXY_DOMAIN_OR_IP\:80:' /etc/nginx/proxy_params_common

    service nginx stop

    /scripts/restartsrv apache_php_fpm
    /scripts/restartsrv_httpd
    service nginx stop
    chkserv_nginx_off

    echo ""
    echo "**************************************"
    echo "*         ngmicro Disabled         *"
    echo "**************************************"
    echo ""
    echo ""
    ;;
	
	
resall)
    echo "========================================="
    echo "=== Restarting All Important Services ==="
    echo "========================================="
    echo ""

    if [ "$(pstree | grep 'crond')" ]; then
        service crond restart
        echo ""
    fi
    if [[ -f /etc/csf/csf.conf && "$(cat /etc/csf/csf.conf | grep 'TESTING = \"0\"')" ]]; then
        csf -r
        echo ""
    fi
    if [ "$(pstree | grep 'lfd')" ]; then
        service lfd restart
        echo ""
    fi
    if [ "$(pstree | grep 'munin-node')" ]; then
        service munin-node restart
        echo ""
    fi
    if [ "$(pstree | grep 'mysql')" ]; then
        /scripts/restartsrv_mysql
        echo ""
    fi
    if [ "$(pstree | grep 'httpd')" ]; then
        echo "Restarting Apache..."
        /scripts/restartsrv apache_php_fpm
        /scripts/restartsrv_httpd
        echo ""
    fi
    if [ "$(pstree | grep 'nginx')" ]; then
        echo "Restarting Nginx..."
        service nginx restart
        echo ""
    fi
    echo ""
    ;;
	
res)
    echo "====================================="
    echo "=== Restarting All Basic Services ==="
    echo "====================================="
    echo ""
    if [ "$(pstree | grep 'httpd')" ]; then
        echo "Restarting Apache..."
        /scripts/restartsrv apache_php_fpm
        /scripts/restartsrv_httpd
        echo ""
    fi
    if [ "$(pstree | grep 'nginx')" ]; then
        echo "Restarting Nginx..."
        service nginx restart
        echo ""
    fi
    echo ""
    ;;
purgecache)
    NOW=$(date +'%Y.%m.%d at %H:%M:%S')
    echo "==================================================================="
    echo "=== Clean Nginx cache & temp folders and restart Apache & Nginx ==="
    echo "==================================================================="
    echo ""
    echo "--- Process started at $NOW ---"
    echo ""
    find /var/cache/nginx/ngmicro_dynamic/ -type f | xargs rm -rvf
    find /var/cache/nginx/ngmicro_static/ -type f | xargs rm -rvf
    find /var/cache/nginx/ngmicro_temp/ -type f | xargs rm -rvf
    if [ "$(pstree | grep 'httpd')" ]; then
        echo "Restarting Apache..."
        /scripts/restartsrv apache_php_fpm
        /scripts/restartsrv_httpd
        echo ""
    fi
    if [ "$(pstree | grep 'nginx')" ]; then
        echo "Restarting Nginx..."
        service nginx restart
        echo ""
    fi
    echo ""
    ;;
purgelogs)
    echo "================================================================"
    echo "=== Clean Nginx access/error logs and restart Apache & Nginx ==="
    echo "================================================================"
    echo ""
    if [ -f /var/log/nginx/access.log ]; then
        echo "" > /var/log/nginx/access.log
    fi
    if [ -f /var/log/nginx/error.log ]; then
        echo "" > /var/log/nginx/error.log
    fi
    if [ "$(pstree | grep 'httpd')" ]; then
        echo "Restarting Apache..."
        /scripts/restartsrv apache_php_fpm
        /scripts/restartsrv_httpd
        echo ""
    fi
    if [ "$(pstree | grep 'nginx')" ]; then
        echo "Restarting Nginx..."
        service nginx restart
        echo ""
    fi
    echo ""
    ;;
fixaccessperms)
    echo "===================================================="
    echo "=== Fix user file & directory access permissions ==="
    echo "===================================================="
    echo ""
    echo "Changing directory permissions to 755..."
    find /home/*/public_html/ -type d -exec chmod 755 {} \;
    echo ""
    echo "Changing file permissions to 644..."
    find /home/*/public_html/ -type f -exec chmod 644 {} \;
    echo ""
    echo "Operation completed."
    echo ""
    echo ""
    ;;
fixownerperms)
    echo "==================================================="
    echo "=== Fix user file & directory owner permissions ==="
    echo "==================================================="
    echo ""
    cd /home
    for user in $( ls -d * )
    do
        if [ -d /home/$user/public_html ]; then
            echo "=== Fixing permissions for user $user ==="
            chown -R $user:$user /home/$user/public_html
            chown $user:nobody /home/$user/public_html
        fi
    done
    echo "Operation completed."
    echo ""
    echo ""
    ;;
restoreipfwd)
    echo "======================================="
    echo "=== Restore IP Forwarding in Apache ==="
    echo "======================================="
    echo ""
    if [[ $GET_HTTPD_VERSION =~ "Apache/2.2." ]]; then
        install_mod_rpaf
    else
        install_mod_remoteip
    fi
    /scripts/restartsrv apache_php_fpm
    /scripts/restartsrv_httpd
    service nginx reload
    echo "Operation completed."
    echo ""
    echo ""
    ;;
cleanup)
    echo "========================================================================="
    echo "=== Cleanup Mac or Windows specific metadata & Apache error_log files ==="
    echo "========================================================================="
    echo ""
    find /home/*/public_html/ -iname 'error_log' | xargs rm -rvf
    find /home/*/public_html/ -iname '.DS_Store' | xargs rm -rvf
    find /home/*/public_html/ -iname 'thumbs.db' | xargs rm -rvf
    find /home/*/public_html/ -iname '__MACOSX' | xargs rm -rvf
    find /home/*/public_html/ -iname '._*' | xargs rm -rvf
    echo ""
    echo "Operation completed."
    echo ""
    echo ""
    ;;
info)
    echo "=================="
    echo "=== OS Version ==="
    echo "=================="
    echo ""
    cat /etc/redhat-release
    echo ""
    echo ""
    echo ""

    echo "=================="
    echo "=== Disk Usage ==="
    echo "=================="
    echo ""
    df -hT
    echo ""
    echo ""

    echo "=============="
    echo "=== Uptime ==="
    echo "=============="
    echo ""
    uptime
    echo ""
    echo ""

    echo "==================="
    echo "=== System Date ==="
    echo "==================="
    echo ""
    date
    echo ""
    echo ""

    echo "======================="
    echo "=== Users Logged In ==="
    echo "======================="
    echo ""
    who
    echo ""
    echo ""
    ;;
80)
    echo "=== Connections on port 80 (HTTP traffic) sorted by connection count & IP ==="
    echo ""
    netstat -anp | grep :80 | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -n
    echo ""
    echo ""
    echo "=== Concurrent connections on port 80 (HTTP traffic) ==="
    echo ""
    netstat -an | grep :80 | wc -l
    echo ""
    echo ""
    ;;
443)
    echo "=== Connections on port 443 (HTTPS traffic) sorted by connection count & IP ==="
    echo ""
    netstat -anp | grep :443 | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -n
    echo ""
    echo ""
    echo "=== Concurrent connections on port 443 (HTTPS traffic) ==="
    echo ""
    netstat -an | grep :443 | wc -l
    echo ""
    echo ""
    ;;
-h|--help|*)
    echo "                 https://www.basezap.com                  "
    cat <<EOF

ngmicro is the best way to use Full-Page Catching with Nginx.

Usage: /ngmicro.sh [command] [flag]

Main commands:
    install          Install, re-install or update ngmicro (enables Nginx by default).
                     Add optional flag "mainline" to install Nginx mainline release.
    remove           Remove ngmicro completely.
    enable           Set Nginx to ports 80/443 & Apache to ports 8080/8443
    disable          Set Nginx to ports 8080/8443 & switch Apache to ports 80/443
    purgecache       Purge Nginx's "cache" & "temp" folders,
                     then restart both Apache & Nginx
    purgelogs        Purge Nginx's access & error log files

Utility commands:
    res              Restart web servers only (Apache & Nginx)
    resall           Restart Cron, CSF & LFD (if installed), Munin (if installed),
                     MySQL, Apache, Nginx
    80               Show active connections on port 80 sorted by connection count & IP,
                     including total concurrent connections count
    443              Show active connections on port 443 sorted by connection count & IP,
                     including total concurrent connections count
    fixaccessperms   Change file & directory access permissions to 644 & 755 respectively
                     in all user /public_html directories
    fixownerperms    Fix owner permissions in all user /public_html directories
    restoreipfwd     Restore Nginx IP forwarding in Apache
    cleanup          Cleanup Mac or Windows specific metadata & Apache error_log files
                     in all user /public_html directories
    info             Show basic system info

~~ Enjoy ngmicro! ~~

EOF
    ;;
esac

# END
