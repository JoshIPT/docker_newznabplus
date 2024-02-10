FROM ubuntu:14.04
MAINTAINER dimaj <dimaj@dimaj.net>

# This container is based on instructions provided here
######
## MUST CHANGE THESE SETTIGNS
######
ENV db_root_pass pass
ENV svn_user SETME
ENV svn_pass SETME
ENV php_timezone America/Los_Angeles

ENV DB_NN_NAME newznab

# news provider hostname
ENV NH_HOST SETME
# news provider port number
ENV NH_PORT SETME
# news provider username
ENV NH_USER SETME
# news provider password
ENV NH_PASS SETME
# news provider is SSL enabled? (true / false)
ENV NH_SSL SETME

#####
## END SETTINGS
#####

# Upgrade system and install required packages
RUN apt-get -y update && apt-get -y upgrade
RUN apt-get install -y software-properties-common php5 php5-dev php-pear \
    php5-gd php5-mysql php5-curl wget apache2 unrar-free lame mediainfo \
    subversion screen tmux vim nano sphinxsearch supervisor


# Install percona server
RUN wget https://repo.percona.com/apt/percona-release_0.1-3.$(lsb_release -sc)_all.deb \
    && dpkg -i percona-release_0.1-3.$(lsb_release -sc)_all.deb \
    && apt-get update \
    && rm percona-release_0.1-3*_all.deb

RUN { \
      echo "percona-server-server-5.6 percona-server-server/root_password password $db_root_pass"; \
      echo "percona-server-server-5.6 percona-server-server/root_password_again password $db_root_pass"; \
    } | debconf-set-selections \
    && apt-get install -y percona-server-server-5.6 percona-server-client-5.6

RUN { \
  echo "phpmyadmin phpmyadmin/dbconfig-install boolean true"; \
  echo "phpmyadmin phpmyadmin/mysql/admin-pass password $db_root_pass"; \
  echo "phpmyadmin phpmyadmin/mysql/app-pass password pma"; \
  echo "phpmyadmin phpmyadmin/app-password-confirm password pma"; \
  echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"; \
} | debconf-set-selections
# install ffmpeg
RUN apt-add-repository ppa:mc3man/trusty-media && apt-get update && service mysql start && apt-get install -y ffmpeg phpmyadmin

# Configure phpmyadmin
COPY ./files/phpmyadmin.conf /usr/share/phpmyadmin/config.inc.php
RUN BF=`grep -oP ".+= \K[^;]+" /var/lib/phpmyadmin/blowfish_secret.inc.php | sed "s/'//g"` /bin/bash -c 'sed -i "s/%%blowfish%%/$BF/" /usr/share/phpmyadmin/config.inc.php'

COPY ./files/websites.conf /etc/apache2/sites-available/websites.conf
RUN a2ensite websites.conf && a2dissite 000-default.conf && a2enmod rewrite && php5enmod mcrypt
RUN service apache2 restart

# Configure phpmyadmin
# RUN service mysql start \
#     && zcat /usr/share/doc/phpmyadmin/examples/create_tables.sql.gz | mysql -uroot -p$db_root_pass

# fix config files
RUN echo "register_globals = Off" >> /etc/php5/apache2/php.ini \
    && sed -i "s/max_execution_time = 30/max_execution_time = 120/" /etc/php5/apache2/php.ini \
    && echo "date.timezone =$php_timezone" >> /etc/php5/apache2/php.ini \
    && echo "group_concat_max_len = 8192" >> /etc/mysql/my.cnf \
    && echo "default_time_zone = '$php_timezone'" >> /etc/mysql/my.cnf \
    && sed -i "s/key_buffer = 16M/key_buffer_size = 16M/" /etc/mysql/my.cnf

RUN service mysql start && mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -uroot -p$db_root_pass mysql

# install newznab
RUN cd /var/www \
    && mkdir newznab \
    && chmod 777 newznab \
    && svn co --username $svn_user --password $svn_pass svn://svn.newznab.com/nn/branches/nnplus /var/www/newznab \
    && chmod 777 /var/www/newznab/www/lib/smarty/templates_c \
    && chmod 777 /var/www/newznab/www/covers/movies \
    && chmod 777 /var/www/newznab/www/covers/anime \
    && chmod 777 /var/www/newznab/www/covers/music \
    && chmod 777 /var/www/newznab/www/covers/tv \
    && chmod 777 /var/www/newznab/www \
    && chmod 777 /var/www/newznab/www/install
    # && chmod 777 /var/www/newznab/nzbfiles

COPY ./files/nn_config.php /var/www/newznab/www/config.php
RUN chmod 777 /var/www/newznab/www/config.php \
    && USER=root /bin/bash -c 'sed -i "s/%%dbuser%%/$USER/" /var/www/newznab/www/config.php' \
    && PASS=$db_root_pass /bin/bash -c 'sed -i "s/%%dbpass%%/$PASS/" /var/www/newznab/www/config.php' \
    && NAME=$DB_NN_NAME /bin/bash -c 'sed -i "s/%%dbname%%/$NAME/" /var/www/newznab/www/config.php' \
    && NAME=$NH_HOST /bin/bash -c 'sed -i "s/%%nhhost%%/$NAME/" /var/www/newznab/www/config.php' \
    && NAME=$NH_PORT /bin/bash -c 'sed -i "s/%%nhport%%/$NAME/" /var/www/newznab/www/config.php' \
    && NAME=$NH_USER /bin/bash -c 'sed -i "s/%%nhuser%%/$NAME/" /var/www/newznab/www/config.php' \
    && NAME=$NH_PASS /bin/bash -c 'sed -i "s/%%nhpass%%/$NAME/" /var/www/newznab/www/config.php' \
    && NAME=$NH_SSL /bin/bash -c 'sed -i "s/%%nhssl%%/$NAME/" /var/www/newznab/www/config.php'

EXPOSE 80
EXPOSE 3306

#add newznab processing script
ADD ./files/newznab.sh /newznab.sh
RUN chmod 755 /*.sh

#Setup supervisor to start Apache and the Newznab scripts to load headers and build releases

RUN mkdir -p /var/lock/apache2 /var/run/apache2 /var/run/sshd /var/log/supervisor
COPY ./files/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Setup NZB volume this will need to be mapped locally using -v command so that it can persist.
VOLUME /nzbs
WORKDIR /var/www/newznab/
#kickoff Supervisor to start the functions
CMD ["/usr/bin/supervisord"]
