#!/usr/bin/env bash

log() {
    if [ $VERBOSE ]; then
        echo $1;
    fi
}

finish()
{
    if [ "$?" -ne 0 ]; then
        echo "Unexpected error has happened."
        remove_host_config
    fi
}

create_project_dir()
{
    log "Creating project dir..."
    if [ ! -d "$CONTAINER_PATH" ]; then
        log "Created $CONTAINER_PATH";
        mkdir -p "$CONTAINER_PATH"
        log "Created!"
    else
        log "Project dir $CONTAINER_PATH already exists."
    fi
}

prepare_ip_address()
{
    DEC_IP=$((MIN_DEC_IP + $TICKET_NUMBER))
    IP_ADDRESS=$(dec2ip "$DEC_IP")

    if [ "$USE_NETWORK_ALIAS" -ne "0" ]; then
        sudo ifconfig "$LOCAL_INTERFACE" alias $IP_ADDRESS up
        if [ $? -ne 0 ]; then
            log "Error! Can't create alias for an interface"
            exit 1
        fi
    fi
}

create_docker_compose_config()
{
    if [ ! -f "$CONTAINER_PATH/docker-compose.yml" ]; then
        log "Create $CONTAINER_PATH/docker-compose.yml";
        cp "$BASE_DIR/template/docker-compose.yml" "$CONTAINER_PATH/docker-compose.yml"
    fi
    file_sed '%ip_address%' "$IP_ADDRESS" "$CONTAINER_PATH"/docker-compose.yml
    file_sed '%img%' "$DOCKER_IMAGE_NAME" "$CONTAINER_PATH"/docker-compose.yml
    file_sed '%magento_version%' "$MAGENTO_VERSION" "$CONTAINER_PATH"/docker-compose.yml
}

run_container()
{
    cd $CONTAINER_PATH
    $DOCKER_COMPOSE up -d

    if [ $? -eq 0 ]; then
        log "Container was created successfully!"
    else
        $DOCKER_COMPOSE down
        rm -Rf $CONTAINER_PATH
        log "Error! Temporary folder was removed!"
        exit 1
    fi
}

create_host_config()
{
    if [ "$CREATE_HOST_CONFIG" -eq "1" ]; then
        log "Create host config $CONTAINERS_HOST_CONFIG_DIR_PATH/$TICKET_NUMBER";
        if [ ! -d $CONTAINERS_HOST_CONFIG_DIR_PATH ]; then
            log "Create $CONTAINERS_HOST_CONFIG_DIR_PATH";
            mkdir -p $CONTAINERS_HOST_CONFIG_DIR_PATH
        fi
        cp "$BASE_DIR/template/hostconf" $CONTAINERS_HOST_CONFIG_DIR_PATH/"$TICKET_NUMBER";
        file_sed '%host%' "$TICKET_NUMBER" $CONTAINERS_HOST_CONFIG_DIR_PATH/"$TICKET_NUMBER"
        file_sed '%ip_address%' "$IP_ADDRESS" $CONTAINERS_HOST_CONFIG_DIR_PATH/"$TICKET_NUMBER"
        file_sed '%dec_ip%' "$DEC_IP" $CONTAINERS_HOST_CONFIG_DIR_PATH/"$TICKET_NUMBER"
    else
        cp "$BASE_DIR/template/hostconf" "$CONTAINER_PATH/hostconf.bak"
        file_sed '%host%' "$TICKET_NUMBER" "$CONTAINER_PATH/hostconf.bak"
        file_sed '%ip_address%' "$IP_ADDRESS" "$CONTAINER_PATH/hostconf.bak"
        file_sed '%dec_ip%' "$DEC_IP" "$CONTAINER_PATH/hostconf.bak"
        cat "$CONTAINER_PATH/hostconf.bak" >> ~/.ssh/config
        rm -f "$CONTAINER_PATH/hostconf.bak"
    fi
}

remove_host_config()
{
    local CONFIG_FILE POSITION LINES OFFSET
    if [ "$CREATE_HOST_CONFIG" -eq "1" ]; then
        CONFIG_FILE="$CONTAINERS_HOST_CONFIG_DIR_PATH/$TICKET_NUMBER"
        log "Remove host configuration file: $CONFIG_FILE"
        rm -Rf $CONTAINERS_HOST_CONFIG_DIR_PATH/"$TICKET_NUMBER"
    else
        log "Remove correspond entry from ~/.ssh/config"
        POSITION=$(grep -n "# $DEC_IP" ~/.ssh/config | sed 's/^\([0-9]\+\):.*$/\1/')
        if [ ! -z $POSITION ]; then
            LINES=$(cat "$BASE_DIR/template/hostconf" | wc -l)
            OFFSET=$((POSITION + $LINES))
            echo $POSITION $LINES $OFFSET
            sed -i "${POSITION},${OFFSET}d" ~/.ssh/config
        fi
    fi
}

mount_container_volume()
{
    local CONTAINER_PATH_SRC
    CONTAINER_PATH_SRC="$CONTAINER_PATH/src/"
    # Mount container volume to the host
    sleep 3;
    log "Mount container volume to the host '$CONTAINER_PATH_SRC'";

    if [ ! -d $CONTAINER_PATH_SRC ]; then
        mkdir -p "$CONTAINER_PATH_SRC";
        log "$CONTAINER_PATH_SRC was created successfully!"
    else
        if [ ! "$(ls -A $CONTAINER_PATH_SRC)" ]
        then
            log "$CONTAINER_PATH_SRC is empty and can be used as mount point"
        else
            log "$CONTAINER_PATH_SRC is not empty and won't be used for mounting"
            return 1
        fi
    fi

    sshfs "$TICKET_NUMBER":/var/www/html/ "$CONTAINER_PATH_SRC" -ocache=no;
    log "Mounted!"
}

set_domain()
{
    # Set own domain
    #
    #sudo sh -c "echo '$IP_ADDRESS     $DOMAIN' >> /etc/hosts"

    local LINE
    db_find "/etc/hosts" "$IP_ADDRESS"
    if [ -z "$POSITION" ]; then
        DOMAIN="$TICKET_NUMBER.$CONTAINERS_DOMAIN_SUFFIX"
        sudo sh -c "echo '$IP_ADDRESS     $DOMAIN' >> /etc/hosts"
    else
        log "Domain for this container is already exists in the /etc/hosts"
        DOMAIN=$(echo $RESULT | awk '{print $2}')
    fi
    log "Domain is '$DOMAIN'"
}


#getLocalValue()
#{
#    PARAMVALUE=`sed -n "/<resources>/,/<\/resources>/p" $LOCALXMLPATH | sed -n -e "s/.*<$1><!\[CDATA\[\(.*\)\]\]><\/$1>.*/\1/p" | head -n 1`
#}

find_and_copy_dumps()
{
    log "Finding code dump..."
    codeDumpFilename=$(find . -maxdepth 1 -name '*.tbz2' -o -name '*.tar.bz2' | head -n1)
    if [ "${codeDumpFilename}" == "" ]
    then
        codeDumpFilename=$(find . -maxdepth 1 -name '*.tar.gz' | grep -v 'logs.tar.gz' | head -n1)
    fi
    if [ ! "$codeDumpFilename" ]
    then
        codeDumpFilename=$(find . -maxdepth 1 -name '*.tgz' | head -n1)
    fi
    if [ ! "$codeDumpFilename" ]
    then
        codeDumpFilename=$(find . -maxdepth 1 -name '*.zip' | head -n1)
    fi

    if [ "$codeDumpFilename" != "" ]
    then
        log "Code dump $codeDumpFilename was copied to container!"
        scp "$codeDumpFilename" $TICKET_NUMBER:/var/www/html
    else
        log "Code dump was not found!"
    fi

    log "Finding db dump..."
    dbdumpFilename=$(find . -maxdepth 1 -name '*.sql.gz' | head -n1)
    if [ ! "$dbdumpFilename" ]
    then
        dbdumpFilename=$(find . -maxdepth 1 -name '*_db.gz' | head -n1)
    fi
    if [ ! "$dbdumpFilename" ]
    then
        dbdumpFilename=$(find . -maxdepth 1 -name '*.sql' | head -n1)
    fi

    if [ "$dbdumpFilename" != "" ]
    then
        log "Database dump $codeDumpFilename was copied to container"
        scp "$dbdumpFilename" $TICKET_NUMBER:/var/www/html
    else
        log "Code dump was not found!"
    fi
}

m2_get_db_param()
{
    PARAM="$1"
    RESULT=$(ssh "$TICKET_NUMBER" "php -r \"\\\$c=include \\\"//var//www//html//app//etc//env.php\\\"; echo \\\$c[\\\"db\\\"][\\\"connection\\\"][\\\"default\\\"][\\\"$PARAM\\\"];\"")
}

m2_is_git()
{
    RESULT=1
    CHECK=$(ssh "$TICKET_NUMBER" "ls /var/www/html/app/code/Magento/AdminNotification/registration.php | grep \"No such\"")
    if [ -z "$CHECK" ]; then
        RESULT=0
    fi
}

m2_is_installed()
{
    RESULT=0
    CHECK=$(ssh "$TICKET_NUMBER" "php -r \"\\\$c=include \\\"//var//www//html//app//etc//env.php\\\"; echo \\\$c[\\\"install\\\"][\\\"date\\\"];\"" | grep "Undefined" | awk NF)
    if [ -z "$CHECK" ]; then
        RESULT=1
    fi
 }

m2_is_correct_domain()
{
    RESULT=0
    CHECK=$(ssh "$TICKET_NUMBER" "mysql $DB_USER $DB_PASSWORD $DB_NAME -e\"SELECT * FROM core_config_data WHERE path like \\\"web%url\\\";\"" | grep "$DOMAIN" | awk NF)
    if [ ! -z "$CHECK" ]; then
        RESULT=1
    fi
}

m2_get_db_credentials()
{
    DB_USER=
    DB_NAME=
    DB_PASSWORD=

    #get db user
    m2_get_db_param "username"
    if [ ! -z "$RESULT" ]; then
        DB_USER="-u$RESULT"
    fi

    #get db name
    m2_get_db_param "dbname"
    if [ ! -z "$RESULT" ]; then
        DB_NAME="$RESULT"
    fi

    #get db user
    m2_get_db_param "password"
    if [ ! -z "$RESULT" ]; then
        DB_PASSWORD="-p$RESULT"
    fi
}

file_sed()
{
    local SEARCH REPLACE SUBJECT
    SEARCH="$1"
    REPLACE="$2"
    SUBJECT="$3"
    if [ "$USE_MAC_SED" -eq "1" ]; then
        sed -i '' s/"$SEARCH"/"$REPLACE"/g "$SUBJECT"
    else
        sed -i s/"$SEARCH"/"$REPLACE"/g "$SUBJECT"
    fi
}

db_add_entry()
{
    local TABLE ENTRY
    TABLE="$1"
    ENTRY="$2"
    RESULT="0"
    POSITION="0"
    echo $ENTRY >> $TABLE
    if [ $? -ne 0 ]; then
        log "Can't write to file $TABLE"
    else
        RESULT="1"
        POSITION=$(grep -n "$ENTRY" $TABLE | head -n1 | awk -F ':' '{print $1}')
    fi
}

db_find()
{
    local TABLE KEYWORD
    POSITION=0
    TABLE="$1"
    KEYWORD="$2"
    RESULT=$(grep "$KEYWORD" $TABLE | head -n1)
    POSITION=$(grep -n "$KEYWORD" $TABLE | head -n1 | awk -F ':' '{print $1}')
}

db_remove_line()
{
    local TABLE LINE
    TABLE="$1"
    LINE="$2"
    RESULT="0"
    sed -i "${LINE}d" "$TABLE"
    if [ $? -ne 0 ]; then
        log "Can't remove a line from file $TABLE"
    else
        RESULT="1"
    fi
}

ip2dec()
{
    # Convert an IPv4 IP number to its decimal equivalent.
    declare -i a b c d;
    IFS=. read a b c d <<<"$1";
    echo "$(((a<<24)+(b<<16)+(c<<8)+d))";
}

dec2ip()
{
    # Convert an IPv4 decimal IP value to an IPv4 IP.
    declare -i a=$((~(-1<<8))) b=$1;
    set -- "$((b>>24&a))" "$((b>>16&a))" "$((b>>8&a))" "$((b&a))";
    local IFS=.;
    echo "$*";
}
