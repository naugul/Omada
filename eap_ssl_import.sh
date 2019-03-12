# CONFIGURATION OPTIONS
EAP_HOSTNAME=rys-informatica.com.ar
EAP_SERVICE=tpeap

# Uncomment following three lines for Debian/Ubuntu
EAP_DIR=/opt/tplink/EAPController
JAVA_DIR=/opt/tplink/EAPController/jre
KEYSTORE=${EAP_DIR}/keystore/eap.keystore

# FOR LET'S ENCRYPT SSL CERTIFICATES ONLY
# Generate your Let's Encrtypt key & cert with certbot before running this script
LE_MODE=yes
LE_LIVE_DIR=/etc/letsencrypt/live

# CONFIGURATION OPTIONS YOU PROBABLY SHOULDN'T CHANGE
ALIAS=eap
PASSWORD=tplink

#### SHOULDN'T HAVE TO TOUCH ANYTHING PAST THIS POINT ####

printf "\nStarting Omada Controller SSL Import...\n"

# Check to see whether Let's Encrypt Mode (LE_MODE) is enabled

if [[ ${LE_MODE} == "YES" || ${LE_MODE} == "yes" || ${LE_MODE} == "Y" || ${LE_MODE} == "y" || ${LE_MODE} == "TRUE" || ${LE_MODE} == "true" || ${LE_MODE} == "ENABLED" || ${LE_MODE} == "enabled" || ${LE_MODE} == 1 ]] ; then
        LE_MODE=true
        printf "\nRunning in Let's Encrypt Mode...\n"
        PRIV_KEY=${LE_LIVE_DIR}/${EAP_HOSTNAME}/privkey.pem
        CHAIN_FILE=${LE_LIVE_DIR}/${EAP_HOSTNAME}/fullchain.pem
else
        LE_MODE=false
        printf "\nRunning in Standard Mode...\n"
fi

if [ ${LE_MODE} == "true" ]; then
        # Check to see whether LE certificate has changed
        printf "\nInspecting current SSL certificate...\n"
        if md5sum -c ${LE_LIVE_DIR}/${EAP_HOSTNAME}/privkey.pem.md5 &>/dev/null; then
                # MD5 remains unchanged, exit the script
                printf "\nCertificate is unchanged, no update is necessary.\n"
#                exit 0
        else
        # MD5 is different, so it's time to get busy!
        printf "\nUpdated SSL certificate available. Proceeding with import...\n"
        fi
fi

# Verify required files exist
if [ ! -f ${PRIV_KEY} ] || [ ! -f ${CHAIN_FILE} ]; then
        printf "\nMissing one or more required files. Check your settings.\n"
        exit 1
else
        # Everything looks OK to proceed
        printf "\nImporting the following files:\n"
        printf "Private Key: %s\n" "$PRIV_KEY"
        printf "CA File: %s\n" "$CHAIN_FILE"
fi

# Create temp files
P12_TEMP=$(mktemp)

# Stop the Omada Controller
printf "\nStopping Omada Controller...\n"
${EAP_SERVICE} stop

if [ ${LE_MODE} == "true" ]; then

        # Write a new MD5 checksum based on the updated certificate
        printf "\nUpdating certificate MD5 checksum...\n"

        md5sum ${PRIV_KEY} > ${LE_LIVE_DIR}/${EAP_HOSTNAME}/privkey.pem.md5

fi

# Create double-safe keystore backup
if [ -s "${KEYSTORE}.orig" ]; then
        printf "\nBackup of original keystore exists!\n"
        printf "\nCreating non-destructive backup as keystore.bak...\n"
        cp ${KEYSTORE} ${KEYSTORE}.bak
else
        cp ${KEYSTORE} ${KEYSTORE}.orig
        printf "\nNo original keystore backup found.\n"
        printf "\nCreating backup as keystore.orig...\n"
fi

# Export your existing SSL key, cert, and CA data to a PKCS12 file
printf "\nExporting SSL certificate and key data into temporary PKCS12 file...\n"

openssl pkcs12 -export \
-in ${CHAIN_FILE} \
-inkey ${PRIV_KEY} \
-out ${P12_TEMP} -passout pass:${PASSWORD} \
-name ${ALIAS}

# Delete the previous certificate data from keystore to avoid "already exists" message
printf "\nRemoving previous certificate data from Omada keystore...\n"
keytool -delete -alias ${ALIAS} -keystore ${KEYSTORE} -deststorepass ${PASSWORD}

# Import the temp PKCS12 file into the Omada keystore
printf "\nImporting SSL certificate into Omada keystore...\n"
keytool -importkeystore \
-srckeystore ${P12_TEMP} -srcstoretype PKCS12 \
-srcstorepass ${PASSWORD} \
-destkeystore ${KEYSTORE} \
-deststorepass ${PASSWORD} \
-destkeypass ${PASSWORD} \
-alias ${ALIAS} -trustcacerts

# Clean up temp files
printf "\nRemoving temporary files...\n"
rm -f ${P12_TEMP}

# Restart the Omada Controller to pick up the updated keystore
printf "\nRestarting Omada Controller to apply new Let's Encrypt SSL certificate...\n"
${EAP_SERVICE} start

# That's all, folks!
printf "\nDone!\n"

exit 0
