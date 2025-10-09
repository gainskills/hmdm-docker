#!/bin/sh
set -e

HMDM_DIR=/opt/hmdm
TEMPLATE_DIR=$HMDM_DIR/templates
TOMCAT_DIR=/usr/local/tomcat
BASE_DIR=$TOMCAT_DIR/work
CACHE_DIR=$BASE_DIR/cache

for DIR in cache files plugins logs; do
   [ -d "$BASE_DIR/$DIR" ] || mkdir -p "$BASE_DIR/$DIR"
done

if [ ! -z "$LOCAL_IP" ]; then
    if ! grep -q "$BASE_DOMAIN" /etc/hosts || [ "$FORCE_RECONFIGURE" = "true" ]; then
        # Create a temporary file for sed output, then overwrite original
        # This is safer than direct in-place editing with `grep -v > /etc/hosts~` then `cp`
        sed "/$BASE_DOMAIN/d" /etc/hosts > /etc/hosts.tmp
        cp /etc/hosts.tmp /etc/hosts
        rm -f /etc/hosts.tmp
        echo "$LOCAL_IP $BASE_DOMAIN" >> /etc/hosts
    fi
fi

HMDM_WAR="$(basename -- $HMDM_URL)"

if [ ! -f "$CACHE_DIR/$HMDM_WAR" ]; then
    wget $DOWNLOAD_CREDENTIALS $HMDM_URL -O $CACHE_DIR/$HMDM_WAR
fi

if [ ! -f "$TOMCAT_DIR/webapps/ROOT.war" ] || [ "$FORCE_RECONFIGURE" = "true" ]; then
    cp -r $CACHE_DIR/$HMDM_WAR $TOMCAT_DIR/webapps/ROOT.war
fi

"$HMDM_DIR/update-web-app-docker.sh"

if [ ! -f "$BASE_DIR/log4j.xml" ] || [ "$FORCE_RECONFIGURE" = "true" ]; then
    cp "$TEMPLATE_DIR/conf/log4j_template.xml" "$BASE_DIR/log4j-hmdm.xml"
fi

if [ ! -d "$BASE_DIR/emails" ] || [ "$FORCE_RECONFIGURE" = "true" ]; then
    cp -r "$TEMPLATE_DIR/emails" "$BASE_DIR/emails"
fi

if [ ! -d "$TOMCAT_DIR/conf/Catalina/localhost" ]; then
    mkdir -p "$TOMCAT_DIR/conf/Catalina/localhost"
fi

SECURE_ENROLLMENT="${SECURE_ENROLLMENT:-0}"
PROTOCOL="${PROTOCOL:-https}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_HOST="${SMTP_HOST:-smtp.office365.com}"
SMTP_FROM="${SMTP_FROM:-info@example.com}"
SMTP_USERNAME="${SMTP_USERNAME:-info@example.com}"
SMTP_PASSWORD="${SMTP_PASSWORD:-changeme}" # Consider managing this via environment or secrets
SMTP_SSL="${SMTP_SSL:-0}"
SMTP_STARTTLS="${SMTP_STARTTLS:-0}"
SMTPSSL_VER="${SMTPSSL_VER:-TLSv1.2}"
MQTT_SERVER_URI=${MQTT_SERVER_URI:-tcp://0.0.0.0:${MQTT_PORT:-31000}}
MQTT_ADMIN_PASSWORD=${MQTT_ADMIN_PASSWORD:-dd3V5YDkrX}
SSL_KEYSTORE_PASSWORD=${SSL_KEYSTORE_PASSWORD:-K8tWyHFTwQtCF8Fp}
MQTT_MSG_DELAY="${MQTT_MSG_DELAY:-100}"
MQTT_CLIENT_TAG="${MQTT_CLIENT_TAG:-}"
MQTT_EXTERNAL="${MQTT_EXTERNAL:-0}"
SEND_STATISTICS="${SEND_STATISTICS:-1}"
HMDM_VARIANT="${HMDM_VARIANT:-os}"
JWT_SECRETKEY="${JWT_SECRETKEY:-20c68f0d9185b1d18cf6add1e8b491fd89529a44}"
JWT_VALIDITY="${JWT_VALIDITY:-86400}"
JWT_VALIDITYREMEMBERME="${JWT_VALIDITYREMEMBERME:-2592000}"

if [ ! -f "$TOMCAT_DIR/conf/Catalina/localhost/ROOT.xml" ] || [ "$FORCE_RECONFIGURE" = "true" ]; then
    # Using # as sed delimiter to avoid issues if variables contain /
    sed \
        -e "s#_SQL_HOST_#$SQL_HOST#g" \
        -e "s#_SQL_PORT_#$SQL_PORT#g" \
        -e "s#_SQL_BASE_#$SQL_BASE#g" \
        -e "s#_SQL_USER_#$SQL_USER#g" \
        -e "s#_SQL_PASS_#$SQL_PASS#g" \
        -e "s#_WEB_PROTOCOL_#$PROTOCOL#g" \
        -e "s#_BASE_DOMAIN_#$BASE_DOMAIN#g" \
        -e "s#_SHARED_SECRET_#$SHARED_SECRET#g" \
        -e "s#_MQTT_SERVER_URI_#$MQTT_SERVER_URI#g" \
        -e "s#_MQTT_ADMIN_PASSWORD_#$MQTT_ADMIN_PASSWORD#g" \
        -e "s#_SSL_KEYSTORE_PASSWORD_#$SSL_KEYSTORE_PASSWORD#g" \
        -e "s#_SMTP_HOST_#$SMTP_HOST#g" \
        -e "s#_SMTP_PORT_#$SMTP_PORT#g" \
        -e "s#_SMTP_SSL_#$SMTP_SSL#g" \
        -e "s#_SMTP_STARTTLS_#$SMTP_STARTTLS#g" \
        -e "s#_SMTP_USERNAME_#$SMTP_USERNAME#g" \
        -e "s#_SMTP_PASSWORD_#$SMTP_PASSWORD#g" \
        -e "s#_SMTP_FROM_#$SMTP_FROM#g" \
        -e "s#_SMTPSSL_VER_#$SMTPSSL_VER#g" \
        -e "s#_MQTT_MSG_DELAY_#$MQTT_MSG_DELAY#g" \
        -e "s#_MQTT_CLIENT_TAG_#$MQTT_CLIENT_TAG#g" \
        -e "s#_MQTT_EXTERNAL_#$MQTT_EXTERNAL#g" \
        -e "s#_SECURE_ENROLLMENT_#$SECURE_ENROLLMENT#g" \
        -e "s#_SEND_STATISTICS_#$SEND_STATISTICS#g" \
        -e "s#_JWT_SECRETKEY_#$JWT_SECRETKEY#g" \
        -e "s#_JWT_VALIDITY_#$JWT_VALIDITY#g" \
        -e "s#_JWT_VALIDITYREMEMBERME_#$JWT_VALIDITYREMEMBERME#g" \
        "$TEMPLATE_DIR/conf/context_template.xml" > "$TOMCAT_DIR/conf/Catalina/localhost/ROOT.xml"
fi

if [ "$INSTALL_LANGUAGE" != "ru" ]; then
    INSTALL_LANGUAGE=en
fi

if [ ! -f "$BASE_DIR/init.sql" ] || [ "$FORCE_RECONFIGURE" = "true" ]; then
    # Using # as sed delimiter
    sed \
        -e "s#_ADMIN_EMAIL_#$ADMIN_EMAIL#g" \
        -e "s#_HMDM_VERSION_#$CLIENT_VERSION#g" \
        -e "s#_HMDM_VARIANT_#$HMDM_VARIANT#g" \
        -e "s#_WEB_PROTOCOL_#$PROTOCOL#g" \
        -e "s#_BASE_DOMAIN_#$BASE_DOMAIN#g" \
        "$TEMPLATE_DIR/sql/hmdm_init.$INSTALL_LANGUAGE.sql" > "$BASE_DIR/init1.sql"

    FILES_TO_DOWNLOAD=$(grep 'https://h-mdm.com' "$BASE_DIR/init1.sql" | awk '{ print $4 }' | sed "s/'//g; s/)//g; s/,//g")

    # Using # as sed delimiter
    sed "s#https://h-mdm.com#$PROTOCOL://$BASE_DOMAIN#g" "$BASE_DIR/init1.sql" > "$BASE_DIR/init.sql"
    rm "$BASE_DIR/init1.sql"
fi

if [ -n "$FILES_TO_DOWNLOAD" ]; then
    ( # Run in a subshell to keep CWD changes local
    cd "$BASE_DIR/files"
    for FILE_URL in $FILES_TO_DOWNLOAD; do
        FILENAME=$(basename "$FILE_URL")
        if [ ! -f "$FILENAME" ]; then # Check relative to current dir ($BASE_DIR/files)
            wget "$FILE_URL"
        fi
    done
    )
fi

# jks is always created from the certificates
if [ "$PROTOCOL" = "https" ]; then
    # Ensure SSL directory exists
    mkdir -p "$TOMCAT_DIR/ssl"
    if [ "$HTTPS_LETSENCRYPT" = "true" ]; then
        HTTPS_CERT_PATH="/etc/letsencrypt/live/$BASE_DOMAIN"
        echo "Looking for SSL keys in $HTTPS_CERT_PATH..."
        # If started by docker-compose, let's wait until certbot completes
        until [ -f "$HTTPS_CERT_PATH/$HTTPS_PRIVKEY" ]; do
            echo "Keys not found, waiting..."
            sleep 5
        done
    fi
    # Ensure variables are set before using them, or handle errors
    if [ -z "$HTTPS_CERT_PATH" ] || [ -z "$HTTPS_PRIVKEY" ] || [ -z "$HTTPS_CERT" ] || [ -z "$HTTPS_FULLCHAIN" ]; then
        echo "Error: One or more HTTPS certificate path variables are not set."
        exit 1
    else
        openssl pkcs12 -export -out "$TOMCAT_DIR/ssl/$BASE_DOMAIN.p12" \
            -inkey "$HTTPS_CERT_PATH/$HTTPS_PRIVKEY" \
            -in "$HTTPS_CERT_PATH/$HTTPS_CERT" \
            -certfile "$HTTPS_CERT_PATH/$HTTPS_FULLCHAIN" \
            -password "pass:$SSL_KEYSTORE_PASSWORD"
        keytool -importkeystore \
            -destkeystore "$TOMCAT_DIR/ssl/$BASE_DOMAIN.jks" \
            -srckeystore "$TOMCAT_DIR/ssl/$BASE_DOMAIN.p12" -srcstoretype PKCS12 \
            -srcstorepass "$SSL_KEYSTORE_PASSWORD" \
            -deststorepass "$SSL_KEYSTORE_PASSWORD" -noprompt

        if [ ! -f "$TOMCAT_DIR/ssl/$BASE_DOMAIN.jks" ]; then
            echo "Error: Failed to create $TOMCAT_DIR/ssl/$BASE_DOMAIN.jks"
            exit 1
        fi
    fi
fi

sed \
    -e "s#_BASE_DOMAIN_#$BASE_DOMAIN#g" \
    -e "s#_SSL_KEYSTORE_PASSWORD_#$SSL_KEYSTORE_PASSWORD#g" \
    "$TEMPLATE_DIR/conf/server_template.xml" > "$TOMCAT_DIR/conf/server.xml"

# Waiting for the database
until PGPASSWORD=$SQL_PASS psql -h "$SQL_HOST" -U "$SQL_USER" -d "$SQL_BASE" -c '\q'; do
  echo "Waiting for the PostgreSQL database..."
  sleep 5
done

# Avoid delays due to an issue with a random number
JAVA_SECURITY_FILE="/opt/java/openjdk/conf/security/java.security"
if [ -f "$JAVA_SECURITY_FILE" ]; then
    # Using # as sed delimiter
    sed 's#securerandom.source=file:/dev/random#securerandom.source=file:/dev/urandom#g' "$JAVA_SECURITY_FILE" > "$JAVA_SECURITY_FILE.tmp" && \
    mv "$JAVA_SECURITY_FILE.tmp" "$JAVA_SECURITY_FILE"
else
    echo "Warning: $JAVA_SECURITY_FILE not found. Skipping modification."
fi

catalina.sh run
#sleep 100000