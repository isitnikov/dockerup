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
    if [ "$POSITION" -ne 0 ]; then
        log "Domain for this container is already exists in the /etc/hosts"
        DOMAIN=$(echo $RESULT | awk '{print $2}')
    else
        DOMAIN="$TICKET_NUMBER.$CONTAINERS_DOMAIN_SUFFIX"
        sudo sh -c "echo '$IP_ADDRESS     $DOMAIN' >> /etc/hosts"
    fi
    log "Domain is '$DOMAIN'"
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
