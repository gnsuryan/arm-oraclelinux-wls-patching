#!/bin/bash

nginx -v

if [ $? == 0 ];
then
  echo "Nginx already installed"
  exit 0
fi

echo "Nginx not installed. Installing Now..."

sudo yum install epel-release
sudo yum install nginx

nginx -v

if [ $? == 0 ];
then
  echo "Nginx installed successfully"
else
  echo "Nginx installation unsuccessfull"
  exit 1
fi

sudo systemctl start nginx

sudo firewall-cmd --permanent --zone=public --add-service=http 
sudo firewall-cmd --permanent --zone=public --add-service=https
sudo firewall-cmd --reload

retCode=$(curl -L -s -o /dev/null -w "%{http_code}" http://localhost/)

if [ "$retCode" == "200" ];
then
  echo "Nginx installed and started successfully"
else
  echo "Nginx installation is successful, but couldn't start Nginx. Please check the logs and try again."
  exit 1
fi
