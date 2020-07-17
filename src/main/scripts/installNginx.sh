#!/bin/bash

function checkIfNginxInstalled()
{
    nginx -v

    if [ $? == 0 ];
    then
      echo "Nginx already installed"
      startNginx
      verifyNginxRunning
      exit 0
    fi
}

function installNginx()
{
  touch /etc/yum.repos.d/nginx.repo

  cat << 'EOF' > /etc/yum.repos.d/nginx.repo
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/rhel/7/$basearch/
gpgcheck=0
enabled=1
EOF

  sudo yum -y install nginx

  nginx -v

  if [ $? == 0 ];
  then
    echo "Nginx installed successfully"
  else
    echo "Nginx installation unsuccessfull"
    exit 1
  fi

}

function startNginx()
{
  sudo systemctl start nginx
  sudo firewall-cmd --permanent --zone=public --add-service=http 
  sudo firewall-cmd --permanent --zone=public --add-service=https
  sudo firewall-cmd --reload
}

function verifyNginxRunning()
{
  curl -L -s http://localhost/

  retCode=$(curl -L -s -o /dev/null -w "%{http_code}" http://localhost/)

  if [ "$retCode" == "200" ];
  then
    echo "Nginx installed and started successfully"
  else
    echo "Nginx installation is successful, but couldn't start Nginx. Please check the logs and try again."
    exit 1
  fi
}


#main

checkIfNginxInstalled
echo "Nginx not installed. Installing Now..."
installNginx
startNginx
verifyNginxRunning
