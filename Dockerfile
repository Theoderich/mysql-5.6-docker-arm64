FROM debian:stretch-slim as builder

RUN set -x \
    && apt-get update \
     && apt-get install -y --no-install-recommends \
     wget \
     cmake \
     make \
     gcc \
     libncurses5-dev \
     build-essential \
     libaio-dev \
     git \
     openssl \
     libssl-dev \
     lsb-release \
     devscripts \
     debhelper \
     po-debconf \
     psmisc \
     libnuma-dev \
     dh-systemd \
     ca-certificates \
     bison \
     sudo \
     zlib1g-dev \
     fakeroot \
    && rm -rf /var/lib/apt/lists/*

ENV MYSQL_VERSION=5.6.36

RUN groupadd -r mysql && useradd -r -g mysql mysql

RUN mkdir mysql && chown mysql:mysql mysql
WORKDIR mysql
USER mysql

RUN wget https://downloads.mysql.com/archives/get/p/23/file/mysql-$MYSQL_VERSION.tar.gz
RUN tar xzf mysql-$MYSQL_VERSION.tar.gz && rm mysql-$MYSQL_VERSION.tar.gz

RUN mkdir /mysql/mysql-$MYSQL_VERSION/bld

WORKDIR /mysql/mysql-$MYSQL_VERSION/bld
RUN cmake .. \
             		-DBUILD_CONFIG=mysql_release \
             		-DCMAKE_INSTALL_PREFIX=/usr \
             		-DINSTALL_DOCDIR=share/mysql/docs \
             		-DINSTALL_DOCREADMEDIR=share/mysql \
             		-DINSTALL_INCLUDEDIR=include/mysql \
              		-DINSTALL_LIBDIR=lib/aarch64-linux-gnu \
             		-DINSTALL_INFODIR=share/mysql/docs \
             		-DINSTALL_MANDIR=share/man \
             		-DINSTALL_MYSQLSHAREDIR=share/mysql \
             		-DINSTALL_MYSQLTESTDIR=lib/mysql-test \
             		-DINSTALL_PLUGINDIR=lib/mysql/plugin \
             		-DINSTALL_SBINDIR=sbin \
             		-DINSTALL_SCRIPTDIR=bin \
             		-DINSTALL_SQLBENCHDIR=lib/mysql \
             		-DINSTALL_SUPPORTFILESDIR=share/mysql \
             		-DMYSQL_DATADIR=/var/lib/mysql \
             		-DSYSCONFDIR=/etc/mysql \
             		-DMYSQL_UNIX_ADDR=/var/run/mysqld/mysqld.sock \
             		-DWITH_SSL=bundled \
             		-DWITH_ZLIB=system \
             		-DWITH_EXTRA_CHARSETS=all \
             		-DWITH_INNODB_MEMCACHED=1 \
             		-DCOMPILATION_COMMENT="MySQL Community Server (GPL)" \
             		-DINSTALL_LAYOUT=DEB
RUN make
User root
RUN make install
WORKDIR /
RUN apt-get purge -y \
         wget \
         cmake \
         make \
         gcc \
         libncurses5-dev \
         build-essential \
         libaio-dev \
         git \
         openssl \
         libssl-dev \
         lsb-release \
         devscripts \
         debhelper \
         po-debconf \
         psmisc \
         libnuma-dev \
         dh-systemd \
         ca-certificates \
         bison \
         zlib1g-dev \
         fakeroot \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /mysql


FROM scratch

COPY --from=builder / /


# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added

RUN apt-get update && apt-get install -y --no-install-recommends gnupg dirmngr && rm -rf /var/lib/apt/lists/*

# add gosu for easy step-down from root
# https://github.com/tianon/gosu/releases
ENV GOSU_VERSION 1.14
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends ca-certificates wget; \
	rm -rf /var/lib/apt/lists/*; \
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	chmod +x /usr/local/bin/gosu; \
	gosu --version; \
	gosu nobody true

RUN mkdir /docker-entrypoint-initdb.d

RUN apt-get update && apt-get install -y --no-install-recommends \
		pwgen \
		perl \
		xz-utils \
	&& rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
		libaio1 libnuma1 \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /

RUN find /etc/mysql/ -name '*.cnf' -print0 \
		| xargs -0 grep -lZE '^(bind-address|log)' \
		| xargs -rt -0 sed -Ei 's/^(bind-address|log)/#&/' \
## don't reverse lookup hostnames, they are usually another container \
    && mkdir -p /etc/mysql/conf.d \
	&& echo '[mysqld]\nskip-host-cache\nskip-name-resolve' > /etc/mysql/conf.d/docker.cnf \
	&& rm -rf /var/lib/apt/lists/* \
	&& rm -rf /var/lib/mysql && mkdir -p /var/lib/mysql /var/run/mysqld \
	&& chown -R mysql:mysql /var/lib/mysql /var/run/mysqld \
## ensure that /var/run/mysqld (used for socket and lock files) is writable regardless of the UID our mysqld instance ends up having at runtime
	&& chmod 1777 /var/run/mysqld /var/lib/mysql
#
VOLUME /var/lib/mysql
#
COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /entrypoint.sh # backwards compat
RUN mkdir /var/lib/mysql-files
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 3306
CMD ["mysqld"]
