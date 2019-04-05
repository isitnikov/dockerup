#!/usr/bin/env bash

BASE_DIR="$(dirname `readlink "$0"`)";

# Include custom config
source "$BASE_DIR/config.sh";
if [ -f "$BASE_DIR/config_custom.sh" ]; then
    source "$BASE_DIR/config_custom.sh";
fi

# Include system files
source "$BASE_DIR/lib.sh";
source "$BASE_DIR/params.sh";
source "$BASE_DIR/init.sh";

trap finish EXIT
trap finish TERM

CONTAINER_PATH="$CONTAINERS_DIR_PATH/$TICKET_NUMBER";

# Create dir for project
create_project_dir

# Prepare IP address
prepare_ip_address

# Create docker-compose.yml
create_docker_compose_config

# Run container
run_container

# Create host config
create_host_config

# Mount container volume
mount_container_volume

# Set domain
set_domain
exit

M2_DUMPS_DEPLOYED=0
if [ "$MAGENTO_VERSION" = "m2" ] && [ "$DOCKER_IMAGE_NAME" = "base" ]
then
    echo "Creating .m2install.conf file..."
    cp "$BASE_DIR/template/.m2install.conf" "$CONTAINER_PATH/.m2install.conf"
    sed -i '' s/%domain%/"$DOMAIN"/g $CONTAINER_PATH/.m2install.conf;
    scp $CONTAINER_PATH/.m2install.conf $TICKET_NUMBER:/var/www/html
    echo "Created!"

    echo "Finding code dump..."
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
        echo "Code dump $codeDumpFilename was copied to container!"
        scp "$codeDumpFilename" $TICKET_NUMBER:/var/www/html
    else
        echo "Code dump was not found!"
    fi

    echo "Finding db dump..."
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
        echo "Database dump $codeDumpFilename was copied to container"
        scp "$dbdumpFilename" $TICKET_NUMBER:/var/www/html
    else
        echo "Code dump was not found!"
    fi

    if [ "$codeDumpFilename" != "" ] && [ "$dbdumpFilename" != "" ]
        echo "Code and database dumps were found. Staring m2install tool..."
        ssh $TICKET_NUMBER "cd /var/www/html; m2install.sh --force"
        M2_DUMPS_DEPLOYED=1
    then
        echo "Code and database dumps were not found. m2install will not run automatically!"
    fi
fi

# Set base url
if [ "$M2_DUMPS_DEPLOYED" != "1" ]
then
    ssh $TICKET_NUMBER "mysql -umagento -p123123q magento -e \"UPDATE core_config_data SET value=\\\"http://$DOMAIN/\\\" WHERE path=\\\"web%url\\\";\""

    echo "Creating config.local.php file..."
    cp "$BASE_DIR/template/config.local.php" "$CONTAINER_PATH/config.local.php"
    sed -i '' s/%domain%/"$DOMAIN"/g $CONTAINER_PATH/config.local.php;
    scp $CONTAINER_PATH/config.local.php $TICKET_NUMBER:/var/www/html/app/etc/
    echo "Created!"
fi

# Cleaning and static deploy
if [ "$MAGENTO_VERSION" = "m2" ] && [ "$M2_DUMPS_DEPLOYED" != "1" ]
then
    ssh $TICKET_NUMBER "sudo rm -Rf /var/www/html/var/*; rm -Rf /var/www/html/pub/static/frontend; rm -Rf /var/www/html/pub/static/adminhtml; rm -Rf /var/www/html/pub/static/_requirejs; cd /var/www/html/; php bin/magento setup:static-content:deploy"
fi

# Enable xdebug for the container
if [ "$XDEBUG" ]; then
    log "Enable xdebug"
    ssh $TICKET_NUMBER "sudo /usr/local/bin/xdebug-sw.sh 1"
fi