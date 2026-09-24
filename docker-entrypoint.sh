#!/bin/sh
set -e

HMDM_DIR=/opt/hmdm
TEMPLATE_DIR=$HMDM_DIR/templates
TOMCAT_DIR=/usr/local/tomcat
BASE_DIR=$TOMCAT_DIR/work
CACHE_DIR=$BASE_DIR/cache

# Escape an environment value first for an XML attribute and then for use as a
# sed replacement. This keeps the existing lightweight template approach while
# allowing generated passwords and URLs to contain XML/sed metacharacters.
xml_sed_escape() {
    printf '%s' "$1" \
        | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' \
        | sed 's/[\\&]/\\&/g'
}

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

HMDM_WAR="$(basename -- "${HMDM_URL%%\?*}")"
# Include the full URL in the cache key. This prevents a temporary test URL
# with the same basename from silently reusing a WAR downloaded from another
# location.
HMDM_CACHE_KEY=$(printf '%s' "$HMDM_URL" | sha256sum | awk '{print $1}')
HMDM_CACHE_FILE="$CACHE_DIR/$HMDM_CACHE_KEY-$HMDM_WAR"
FORCE_WAR_UPDATE="${FORCE_WAR_UPDATE:-false}"
# Extract domain from HMDM_URL (e.g., extract https://mdm-files.gainskills.top from https://mdm-files.gainskills.top/hmdm-5.37.3-os.war)
HMDM_URL_DOMAIN=$(echo "$HMDM_URL" | sed -E 's|^(https?://[^/]+).*|\1|')

if [ -f "$HMDM_CACHE_FILE" ] && { [ "$FORCE_RECONFIGURE" = "true" ] || [ "$FORCE_WAR_UPDATE" = "true" ]; }; then
    rm -f "$HMDM_CACHE_FILE"
fi

if [ ! -f "$HMDM_CACHE_FILE" ]; then
    if ! wget $DOWNLOAD_CREDENTIALS "$HMDM_URL" -O "$HMDM_CACHE_FILE"; then
        echo "Failed to retrieve $HMDM_URL!"
        rm -f "$HMDM_CACHE_FILE"
        exit 1
    fi
fi

if [ -n "$HMDM_WAR_SHA256" ] && ! printf '%s  %s\n' "$HMDM_WAR_SHA256" "$HMDM_CACHE_FILE" | sha256sum -c -; then
    echo "Checksum verification failed for $HMDM_URL"
    rm -f "$HMDM_CACHE_FILE"
    exit 1
fi

if [ ! -f "$TOMCAT_DIR/webapps/ROOT.war" ] || [ "$FORCE_RECONFIGURE" = "true" ] || [ "$FORCE_WAR_UPDATE" = "true" ]; then
    cp "$HMDM_CACHE_FILE" "$TOMCAT_DIR/webapps/ROOT.war"
fi

"$HMDM_DIR/update-web-app-docker.sh"

if [ ! -f "$BASE_DIR/logback-hmdm.xml" ] || [ "$FORCE_RECONFIGURE" = "true" ]; then
    cp "$TEMPLATE_DIR/conf/logback_template.xml" "$BASE_DIR/logback-hmdm.xml"
fi

if [ ! -d "$BASE_DIR/emails" ] || [ "$FORCE_RECONFIGURE" = "true" ]; then
    cp -r "$TEMPLATE_DIR/emails" "$BASE_DIR/"
fi

if [ ! -d "$TOMCAT_DIR/conf/Catalina/localhost" ]; then
    mkdir -p "$TOMCAT_DIR/conf/Catalina/localhost"
fi

# USAGE_SCENARIO: private / shared; shared can be used only in Enterprise solution
USAGE_SCENARIO="${USAGE_SCENARIO:-private}"
SECURE_ENROLLMENT="${SECURE_ENROLLMENT:-1}"
STRICT_TRANSPORT_SECURITY="${STRICT_TRANSPORT_SECURITY:-0}"
PREVENT_DUPLICATE_ENROLLMENT="${PREVENT_DUPLICATE_ENROLLMENT:-0}"
LAUNCHER_PACKAGE="${LAUNCHER_PACKAGE:-com.hmdm.launcher}"
DEVICE_ALLOWED_ADDRESS="${DEVICE_ALLOWED_ADDRESS:-}"
UI_ALLOWED_ADDRESS="${UI_ALLOWED_ADDRESS:-}"

PROTOCOL="${PROTOCOL:-https}"
if [ -z "$BASE_DOMAIN" ]; then
    echo "Error: BASE_DOMAIN must be set"
    exit 1
fi
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-$PROTOCOL://$BASE_DOMAIN}"
HTTPS_CERT_PATH="${HTTPS_CERT_PATH:-/etc/letsencrypt/live/$BASE_DOMAIN}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_HOST="${SMTP_HOST:-smtp.office365.com}"
SMTP_FROM="${SMTP_FROM:-info@example.com}"
SMTP_USERNAME="${SMTP_USERNAME:-info@example.com}"
SMTP_PASSWORD="${SMTP_PASSWORD:-changeme}" # Consider managing this via environment or secrets
SMTP_SSL="${SMTP_SSL:-0}"
SMTP_STARTTLS="${SMTP_STARTTLS:-0}"
SMTPSSL_VER="${SMTPSSL_VER:-TLSv1.2}"
MQTT_PORT="${MQTT_PORT:-31000}"
MQTT_SERVER_URI=${MQTT_SERVER_URI:-tcp://0.0.0.0:$MQTT_PORT}
MQTT_ADMIN_PASSWORD=${MQTT_ADMIN_PASSWORD:-dd3V5YDkrX}
MQTT_MSG_DELAY="${MQTT_MSG_DELAY:-100}"
MQTT_CLIENT_TAG="${MQTT_CLIENT_TAG:-hmdm}"
MQTT_EXTERNAL="${MQTT_EXTERNAL:-0}"

# Older examples omitted the MQTT port. Keep the externally published and
# broker listener ports aligned instead of falling back to 1883/8883.
case "$MQTT_SERVER_URI" in
    *://*) MQTT_AUTHORITY=${MQTT_SERVER_URI#*://} ;;
    *) MQTT_AUTHORITY=$MQTT_SERVER_URI ;;
esac
case "$MQTT_AUTHORITY" in
    \[*\]:[0-9]*|*:[0-9]*) ;;
    *) MQTT_SERVER_URI="${MQTT_SERVER_URI%/}:$MQTT_PORT" ;;
esac

# When serving HTTPS with the embedded broker, run MQTT over TLS too (ssl:// scheme).
# The broker reads its certificate from the PEM paths in context.xml (ssl.pem.*) and
# reloads it in-process. Preserve host:port; leave external-broker URIs untouched.
if [ "$MQTT_EXTERNAL" != "1" ] && [ "$PROTOCOL" = "https" ]; then
    MQTT_SERVER_URI="ssl://$(echo "$MQTT_SERVER_URI" | sed -E 's#^[a-z+]+://##')"
fi
SEND_STATISTICS="${SEND_STATISTICS:-0}"
HMDM_VARIANT="${HMDM_VARIANT:-os}"
JWT_SECRETKEY="${JWT_SECRETKEY:-20c68f0d9185b1d18cf6add1e8b491fd89529a44}"
JWT_VALIDITY="${JWT_VALIDITY:-86400}"
JWT_VALIDITYREMEMBERME="${JWT_VALIDITYREMEMBERME:-2592000}"
REBRANDING_NAME="${REBRANDING_NAME:-}"
REBRANDING_VENDOR_NAME="${REBRANDING_VENDOR_NAME:-}"
REBRANDING_VENDOR_LINK="${REBRANDING_VENDOR_LINK:-}"
REBRANDING_SIGNUP_LINK="${REBRANDING_SIGNUP_LINK:-}"
REBRANDING_TERMS_LINK="${REBRANDING_TERMS_LINK:-}"

if [ ! -f "$TOMCAT_DIR/conf/Catalina/localhost/ROOT.xml" ] || [ "$FORCE_RECONFIGURE" = "true" ]; then
    # Using Ctrl+A (hex 01) as a delimiter because it's almost never in a password
	    DELIM=$(printf '\001')
	    sed \
	        -e "s${DELIM}_USAGE_SCENARIO_${DELIM}$(xml_sed_escape "$USAGE_SCENARIO")${DELIM}g" \
	        -e "s${DELIM}_SECURE_ENROLLMENT_${DELIM}$(xml_sed_escape "$SECURE_ENROLLMENT")${DELIM}g" \
	        -e "s${DELIM}_STRICT_TRANSPORT_SECURITY_${DELIM}$(xml_sed_escape "$STRICT_TRANSPORT_SECURITY")${DELIM}g" \
	        -e "s${DELIM}_PREVENT_DUPLICATE_ENROLLMENT_${DELIM}$(xml_sed_escape "$PREVENT_DUPLICATE_ENROLLMENT")${DELIM}g" \
	        -e "s${DELIM}_LAUNCHER_PACKAGE_${DELIM}$(xml_sed_escape "$LAUNCHER_PACKAGE")${DELIM}g" \
	        -e "s${DELIM}_SQL_HOST_${DELIM}$(xml_sed_escape "$SQL_HOST")${DELIM}g" \
	        -e "s${DELIM}_SQL_PORT_${DELIM}$(xml_sed_escape "$SQL_PORT")${DELIM}g" \
	        -e "s${DELIM}_SQL_BASE_${DELIM}$(xml_sed_escape "$SQL_BASE")${DELIM}g" \
	        -e "s${DELIM}_SQL_USER_${DELIM}$(xml_sed_escape "$SQL_USER")${DELIM}g" \
	        -e "s${DELIM}_SQL_PASS_${DELIM}$(xml_sed_escape "$SQL_PASS")${DELIM}g" \
	        -e "s${DELIM}_WEB_PROTOCOL_${DELIM}$(xml_sed_escape "$PROTOCOL")${DELIM}g" \
	        -e "s${DELIM}_BASE_DOMAIN_${DELIM}$(xml_sed_escape "$BASE_DOMAIN")${DELIM}g" \
	        -e "s${DELIM}_PUBLIC_BASE_URL_${DELIM}$(xml_sed_escape "$PUBLIC_BASE_URL")${DELIM}g" \
	        -e "s${DELIM}_SHARED_SECRET_${DELIM}$(xml_sed_escape "$SHARED_SECRET")${DELIM}g" \
	        -e "s${DELIM}_MQTT_SERVER_URI_${DELIM}$(xml_sed_escape "$MQTT_SERVER_URI")${DELIM}g" \
	        -e "s${DELIM}_MQTT_ADMIN_PASSWORD_${DELIM}$(xml_sed_escape "$MQTT_ADMIN_PASSWORD")${DELIM}g" \
	        -e "s${DELIM}_HTTPS_PRIVKEY_${DELIM}$(xml_sed_escape "$HTTPS_PRIVKEY")${DELIM}g" \
	        -e "s${DELIM}_HTTPS_FULLCHAIN_${DELIM}$(xml_sed_escape "$HTTPS_FULLCHAIN")${DELIM}g" \
	        -e "s${DELIM}_HTTPS_CERT_PATH_${DELIM}$(xml_sed_escape "$HTTPS_CERT_PATH")${DELIM}g" \
	        -e "s${DELIM}_SMTP_HOST_${DELIM}$(xml_sed_escape "$SMTP_HOST")${DELIM}g" \
	        -e "s${DELIM}_SMTP_PORT_${DELIM}$(xml_sed_escape "$SMTP_PORT")${DELIM}g" \
	        -e "s${DELIM}_SMTP_SSL_${DELIM}$(xml_sed_escape "$SMTP_SSL")${DELIM}g" \
	        -e "s${DELIM}_SMTP_STARTTLS_${DELIM}$(xml_sed_escape "$SMTP_STARTTLS")${DELIM}g" \
	        -e "s${DELIM}_SMTP_USERNAME_${DELIM}$(xml_sed_escape "$SMTP_USERNAME")${DELIM}g" \
	        -e "s${DELIM}_SMTP_PASSWORD_${DELIM}$(xml_sed_escape "$SMTP_PASSWORD")${DELIM}g" \
	        -e "s${DELIM}_SMTP_FROM_${DELIM}$(xml_sed_escape "$SMTP_FROM")${DELIM}g" \
	        -e "s${DELIM}_SMTPSSL_VER_${DELIM}$(xml_sed_escape "$SMTPSSL_VER")${DELIM}g" \
	        -e "s${DELIM}_MQTT_MSG_DELAY_${DELIM}$(xml_sed_escape "$MQTT_MSG_DELAY")${DELIM}g" \
	        -e "s${DELIM}_MQTT_CLIENT_TAG_${DELIM}$(xml_sed_escape "$MQTT_CLIENT_TAG")${DELIM}g" \
	        -e "s${DELIM}_MQTT_EXTERNAL_${DELIM}$(xml_sed_escape "$MQTT_EXTERNAL")${DELIM}g" \
	        -e "s${DELIM}_SEND_STATISTICS_${DELIM}$(xml_sed_escape "$SEND_STATISTICS")${DELIM}g" \
	        -e "s${DELIM}_JWT_SECRETKEY_${DELIM}$(xml_sed_escape "$JWT_SECRETKEY")${DELIM}g" \
	        -e "s${DELIM}_JWT_VALIDITY_${DELIM}$(xml_sed_escape "$JWT_VALIDITY")${DELIM}g" \
	        -e "s${DELIM}_JWT_VALIDITYREMEMBERME_${DELIM}$(xml_sed_escape "$JWT_VALIDITYREMEMBERME")${DELIM}g" \
	        -e "s${DELIM}_REBRANDING_NAME_${DELIM}$(xml_sed_escape "$REBRANDING_NAME")${DELIM}g" \
	        -e "s${DELIM}_REBRANDING_VENDOR_NAME_${DELIM}$(xml_sed_escape "$REBRANDING_VENDOR_NAME")${DELIM}g" \
	        -e "s${DELIM}_REBRANDING_VENDOR_LINK_${DELIM}$(xml_sed_escape "$REBRANDING_VENDOR_LINK")${DELIM}g" \
	        -e "s${DELIM}_REBRANDING_SIGNUP_LINK_${DELIM}$(xml_sed_escape "$REBRANDING_SIGNUP_LINK")${DELIM}g" \
	        -e "s${DELIM}_REBRANDING_TERMS_LINK_${DELIM}$(xml_sed_escape "$REBRANDING_TERMS_LINK")${DELIM}g" \
	        -e "s${DELIM}_DEVICE_ALLOWED_ADDRESS_${DELIM}$(xml_sed_escape "$DEVICE_ALLOWED_ADDRESS")${DELIM}g" \
	        -e "s${DELIM}_UI_ALLOWED_ADDRESS_${DELIM}$(xml_sed_escape "$UI_ALLOWED_ADDRESS")${DELIM}g" \
	        "$TEMPLATE_DIR/conf/context_template.xml" > "$TOMCAT_DIR/conf/Catalina/localhost/ROOT.xml"

    # Uncomment the IP restriction lines only when the variables are set
    ROOT_XML="$TOMCAT_DIR/conf/Catalina/localhost/ROOT.xml"
    if [ -n "$DEVICE_ALLOWED_ADDRESS" ]; then
        sed -i 's|<!-- <Parameter name="device.allowed.address" value="\(.*\)"/> -->|<Parameter name="device.allowed.address" value="\1"/>|g' "$ROOT_XML"
    fi
    if [ -n "$UI_ALLOWED_ADDRESS" ]; then
        sed -i 's|<!-- <Parameter name="ui.allowed.address" value="\(.*\)"/> -->|<Parameter name="ui.allowed.address" value="\1"/>|g' "$ROOT_XML"
    fi

    # Uncomment rebranding lines only when the variables are set (Enterprise only)
    if [ -n "$REBRANDING_NAME" ]; then
        sed -i 's|<!-- <Parameter name="rebranding.name" value="\(.*\)"/> -->|<Parameter name="rebranding.name" value="\1"/>|g' "$ROOT_XML"
        sed -i 's|<!-- <Parameter name="rebranding.mobile.name" value="\(.*\)"/> -->|<Parameter name="rebranding.mobile.name" value="\1"/>|g' "$ROOT_XML"
    fi
    if [ -n "$REBRANDING_VENDOR_NAME" ]; then
        sed -i 's|<!-- <Parameter name="rebranding.vendor.name" value="\(.*\)"/> -->|<Parameter name="rebranding.vendor.name" value="\1"/>|g' "$ROOT_XML"
    fi
    if [ -n "$REBRANDING_VENDOR_LINK" ]; then
        sed -i 's|<!-- <Parameter name="rebranding.vendor.link" value="\(.*\)"/> -->|<Parameter name="rebranding.vendor.link" value="\1"/>|g' "$ROOT_XML"
    fi
    if [ -n "$REBRANDING_SIGNUP_LINK" ]; then
        sed -i 's|<!-- <Parameter name="rebranding.signup.link" value="\(.*\)"/> -->|<Parameter name="rebranding.signup.link" value="\1"/>|g' "$ROOT_XML"
    fi
    if [ -n "$REBRANDING_TERMS_LINK" ]; then
        sed -i 's|<!-- <Parameter name="rebranding.terms.link" value="\(.*\)"/> -->|<Parameter name="rebranding.terms.link" value="\1"/>|g' "$ROOT_XML"
    fi
fi

# Migrate persisted pre-Java-21 context files without overwriting unrelated
# operator customizations. FORCE_RECONFIGURE remains available for a full reset.
ROOT_XML="$TOMCAT_DIR/conf/Catalina/localhost/ROOT.xml"
if grep -q 'name="log4j.config"' "$ROOT_XML"; then
    echo "Migrating persisted logging configuration from Log4j to Logback..."
    sed -i \
        -e 's/name="log4j.config"/name="logback.config"/' \
        -e 's#log4j-hmdm\.xml#logback-hmdm.xml#' \
        "$ROOT_XML"
fi

if grep -q 'name="ssl.keystore.password"' "$ROOT_XML"; then
    echo "Migrating persisted MQTT TLS configuration from JKS to PEM..."
    sed -i \
        -e "/name=\"ssl.keystore.password\"/c\\    <Parameter name=\"ssl.pem.key.path\" value=\"$HTTPS_CERT_PATH/$HTTPS_PRIVKEY\"/>" \
        -e "/name=\"ssl.keystore.path\"/c\\    <Parameter name=\"ssl.pem.cert.path\" value=\"$HTTPS_CERT_PATH/$HTTPS_FULLCHAIN\"/>" \
        "$ROOT_XML"
    if [ "$MQTT_EXTERNAL" != "1" ]; then
        sed -i \
            "/name=\"mqtt.server.uri\"/c\\    <Parameter name=\"mqtt.server.uri\" value=\"$MQTT_SERVER_URI\"/>" \
            "$ROOT_XML"
    fi
fi

# Java 21 Artemis watches this shared file for an atomic replace after Certbot
# renews the PEM files. Add it to existing PEM-based configurations as well as
# newly generated ones.
if grep -q 'name="ssl.pem.cert.path"' "$ROOT_XML" && ! grep -q 'name="ssl.pem.config.path"' "$ROOT_XML"; then
    sed -i \
        '/name="ssl.pem.cert.path"/a\    <Parameter name="ssl.pem.config.path" value="/var/lib/hmdm/mqtt/mqtt-broker.pemcfg"/>' \
        "$ROOT_XML"
fi

if [ "$INSTALL_LANGUAGE" != "ru" ]; then
    INSTALL_LANGUAGE=en
fi

if [ ! -f "$BASE_DIR/init.sql" ] || [ "$FORCE_RECONFIGURE" = "true" ]; then
    # Using # as sed delimiter
    sed \
        -e "s#_ADMIN_EMAIL_#$ADMIN_EMAIL#g" \
        -e "s#_HMDM_CLIENT_VERSION_#$CLIENT_VERSION#g" \
        -e "s#_HMDM_VARIANT_#$HMDM_VARIANT#g" \
        -e "s#_WEB_PROTOCOL_#$PROTOCOL#g" \
        -e "s#_BASE_DOMAIN_#$BASE_DOMAIN#g" \
        "$TEMPLATE_DIR/sql/hmdm_init.$INSTALL_LANGUAGE.sql" > "$BASE_DIR/init1.sql"

    FILES_TO_DOWNLOAD=$(grep 'https://h-mdm.com' "$BASE_DIR/init1.sql" | awk '{ print $4 }' | sed "s/'//g; s/)//g; s/,//g; s/;//g")

    # Using # as sed delimiter
    sed "s#https://h-mdm.com#$PUBLIC_BASE_URL#g" "$BASE_DIR/init1.sql" > "$BASE_DIR/init.sql"
    rm "$BASE_DIR/init1.sql"
fi

if [ -n "$FILES_TO_DOWNLOAD" ]; then
    ( # Run in a subshell to keep CWD changes local
    cd "$BASE_DIR/files"
    for FILE_URL in $FILES_TO_DOWNLOAD; do
        # Replace hardcoded domain with HMDM_URL_DOMAIN - fixed port 8443
        FILE_URL=$(echo "$FILE_URL" | sed "s#https://h-mdm.com#$HMDM_URL_DOMAIN#g")
        FILENAME=$(basename "$FILE_URL")
        if [ ! -f "$FILENAME" ]; then # Check relative to current dir ($BASE_DIR/files)
            wget "$FILE_URL"
        fi
    done
    )
fi

# HTTPS uses certbot PEM files directly (Tomcat connector + MQTT broker over TLS).
# Validate the files are present so a misconfiguration fails fast and clearly.
if [ "$PROTOCOL" = "https" ]; then
    if [ "$HTTPS_LETSENCRYPT" = "true" ]; then
        echo "Looking for SSL keys in $HTTPS_CERT_PATH..."
        # If started by docker-compose, let's wait until certbot completes
        until [ -f "$HTTPS_CERT_PATH/$HTTPS_PRIVKEY" ]; do
            echo "Keys not found, waiting..."
            sleep 5
        done
    fi
    for CERT_FILE in "$HTTPS_PRIVKEY" "$HTTPS_CERT" "$HTTPS_FULLCHAIN"; do
        if [ ! -f "$HTTPS_CERT_PATH/$CERT_FILE" ]; then
            echo "Error: certificate file $HTTPS_CERT_PATH/$CERT_FILE not found"
            exit 1
        fi
    done
fi

DELIM=$(printf '\001')
sed \
    -e "s${DELIM}_HTTPS_CERT_PATH_${DELIM}$(xml_sed_escape "$HTTPS_CERT_PATH")${DELIM}g" \
    -e "s${DELIM}_HTTPS_PRIVKEY_${DELIM}$(xml_sed_escape "$HTTPS_PRIVKEY")${DELIM}g" \
    -e "s${DELIM}_HTTPS_CERT_${DELIM}$(xml_sed_escape "$HTTPS_CERT")${DELIM}g" \
    -e "s${DELIM}_HTTPS_FULLCHAIN_${DELIM}$(xml_sed_escape "$HTTPS_FULLCHAIN")${DELIM}g" \
    "$TEMPLATE_DIR/conf/server_template.xml" > "$TOMCAT_DIR/conf/server.xml"

if [ "$PROTOCOL" != "https" ]; then
    sed -i \
        -e '/org.apache.catalina.security.TLSCertificateReloadListener/d' \
        -e '/HMDM_HTTPS_CONNECTOR_START/,/HMDM_HTTPS_CONNECTOR_END/d' \
        "$TOMCAT_DIR/conf/server.xml"
fi

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

exec catalina.sh run
#sleep 100000
