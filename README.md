# dockerup
#### The script automates some routine operations with containers:
1. Create project directory (named such as ticket number or magento version).
2. Create docker-compose.yml.
3. Run container.
4. Create host config.
5. Mount container volume to your file system.

#### You can run several containers simultaneously. Each container will have own IP address.

### Installing: 
    cd ~/scripts
    git clone https://github.com/doit24365/dockerup.git
    cd dockerup
    chmod +x dockerup.sh

### Before usage:
#### Insert to file ~/.ssh/config:
        Include cnt_cnf/*
#### Create file config_custom.sh with custom params for overriding config if need
    
### Usage:
    Help:           ~/work/scripts/dockerup/dockerup.sh -h
    Run container:  ~/work/scripts/dockerup/dockerup.sh -t 214 -i 2.1.4-git-sd -v
    Frontend:       http://127.0.21.4/
    MailCatcher:    http://127.0.21.4:81/
    ssh:            ssh 214
    
### Notes for working from Windows 10 
1. Install docker on Windows 10
2. Enable *Expose daemon on tcp://localhost:2375 without TLS* in *Settings > General*
3. Install CLI applications in Linux subsystem: ```sudo apt-get install docker docker-compose```
4. Add ```export DOCKER_HOST=tcp://0.0.0.0:2375``` into *~/.bashrc* file
   
