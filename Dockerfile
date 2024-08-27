# syntax=docker/dockerfile:1
FROM tomcat:9-jdk11-temurin-jammy

Arg WEB_PANEL_VER=5.27.2 \
	CLIENT_VERSION=5.28 \
	HMDM_VARIANT=os

RUN apt-get update -y && apt-get upgrade -y \
	&& apt-get install -y --no-install-recommends \
	aapt \
	wget \
	sed \
	postgresql-client \
	&& apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /usr/local/tomcat/conf/Catalina/localhost \
    && mkdir -p /usr/local/tomcat/ssl

# Available values of INSTALL_LANGUAGE: en, ru (en by default)
# value of SHARED_SECRET should be different for open source and premium versions!
ENV	INSTALL_LANGUAGE=en \
	SHARED_SECRET=changeme-C3z9vi54 \
	DOWNLOAD_CREDENTIALS= \
	HMDM_URL=https://h-mdm.com/files/hmdm-${WEB_PANEL_VER}-${HMDM_VARIANT}.war \
	CLIENT_VERSION=${CLIENT_VERSION} \
	SQL_HOST=localhost \
	SQL_PORT=5432 \
	SQL_BASE=hmdm \
	SQL_USER=hmdm \
	SQL_PASS=Ch@nGeMe \
	SMTP_HOST=smtp.office365.com \
	SMTP_PORT=587 \
	SMTP_SSL=0 \
	SMTP_STARTTLS=1 \
	SMTP_FROM=cinfo@example.com \
	SMTP_USERNAME=cinfo@example.com \
	SMTP_PASSWORD=changeme \
	SMTP-SSL_VER=TLSv1.2 \
	# ADMIN_EMAIL=
	PROTOCOL=https \
	# BASE_DOMAIN=your-domain.com
	# LOCAL_IP=172.31.91.82 # Set this parameter to your local IP address
	# Comment following line to use custom certificates
    HTTPS_LETSENCRYPT=true \
# Mount the custom certificate path if custom certificates must be used
# ENV_HTTPS_CERT_PATH is the path to certificates and keys inside the container
	# HTTPS_CERT_PATH=/cert
	HTTPS_CERT=cert.pem \
	HTTPS_FULLCHAIN=fullchain.pem \
	HTTPS_PRIVKEY=privkey.pem

# Set to 1 to force updating the config files
# If not set, they will be created only if there's no files
	# FORCE_RECONFIGURE=true

EXPOSE ${HTTP_PORT} \
	   ${HTTPS_PORT} \
	   ${MQTT_PORT}

COPY docker-entrypoint.sh /
COPY tomcat_conf/server.xml /usr/local/tomcat/conf/server.xml
COPY templates/ /opt/hmdm/templates/

ENTRYPOINT ["/docker-entrypoint.sh"]
