#!/bin/bash

rand=$(openssl rand 4 2>/dev/null | od -DAn)

# remove leading whitespace
rand="$(echo -e "${rand}" | tr -d '[:space:]')"

echo "Welcome to Hopsworks!"

echo ""
echo ""
echo "[Legal stuff]"
echo "Logical Clocks AB will use the information you provide during the registration"
echo "to be in touch with you to provide updates and marketing."
echo "You can opt out at any time by clicking the unsubscribe link in the"
echo "footer of any email you receive from us, or by contacting us at jim@logicalclocks.com"
echo "By continuing the registration you agree that we may process your information in"
echo "accordance with these terms."

echo ""
echo ""
echo "Please enter your email address to continue:"
read email

if [[ $email =~ .*@.* ]]
then
  echo "Registering hopsworks instance...."
  echo "{\"id\": \"$rand\", \"name\":\"$email\"}" > .details
else
  echo "Exiting. Invalid email"
  exit 1
fi

curl -H "Content-type:application/json" --data @.details http://snurran.sics.se:8443/keyword

echo "Generating a certificate for your instance..."
export HOST=$(hostname -A)

sudo rm -f /srv/hops/domains/domain1/config/keystore.jks

sudo keytool -genkey -noprompt -trustcacerts -keyalg RSA -alias s1as -dname cn=$HOST -keypass adminpw -keystore /srv/hops/domains/domain1/config/keystore.jks -storepass adminpw

sudo keytool -export -noprompt -alias s1as -file /tmp/cert.pem -keystore /srv/hops/domains/domain1/config/keystore.jks -storepass adminpw -rfc

sudo keytool -delete -alias s1as -keystore /srv/hops/domains/domain1/config/cacerts.jks -noprompt -storepass adminpw

sudo keytool -import -noprompt -trustcacerts -alias s1as -file /tmp/cert.pem -keystore /srv/hops/domains/domain1/config/cacerts.jks -storepass adminpw

# Make sure the db is running before running the query
echo "Configuring the instance"
sudo systemctl start ndb_mgmd
sudo systemctl start ndbmtd
sudo systemctl start mysqld
export ENDPOINT=${HOST//[[:space:]]/}:443
sudo /srv/hops/mysql-cluster/ndb/scripts/mysql-client.sh hopsworks -e "update variables set value='$ENDPOINT' where id='hopsworks_endpoint'"

sudo sh -c "echo '127.0.0.1 $HOSTNAME' >> /etc/hosts"

echo "Starting all the services..."
# Make sure the resourcemanager is down - otherwise it won't pick up the new JWT token
sudo systemctl stop resourcemanager
sudo systemctl start glassfish-domain1
JWT=`curl -XPOST https://127.0.0.1:443/hopsworks-api/api/auth/login --data 'email=agent%40hops.io&password=admin' -k -i -s --header 'Content-Type: application/x-www-form-urlencoded' | grep Authorization | awk '{split($0,a," "); print a[2] " " a[3];}' | tr -d '\r'`
RMJWT=`curl -XPOST https://127.0.0.1:443/hopsworks-api/api/auth/login --data 'email=agent%40hops.io&password=admin' -k -i -s --header 'Content-Type: application/x-www-form-urlencoded' | grep Authorization | awk '{split($0,a," "); print a[3];}' | tr -d '\r'`

#sudo sed -i 's/JWTPLACEHOLDER/'"$RMJWT"'/' /srv/hops/hadoop/etc/hadoop/ssl-server.xml
sudo /srv/hops/kagent/kagent/bin/start-all-local-services.sh

# Generate new JWT for Hopsworks internal comm and update the variables entry
#sudo /srv/hops/mysql-cluster/ndb/scripts/mysql-client.sh hopsworks -e "update variables set value='$JWT' where id='service_jwt'"

sudo cp /srv/hops/domains/domain1/config/cacerts.jks /tmp/
sudo chmod 755 /tmp/cacerts.jks
sudo -u hdfs /srv/hops/hadoop/bin/hdfs dfs -rm -f /user/spark/cacerts.jks
sudo -u hdfs /srv/hops/hadoop/bin/hdfs dfs -copyFromLocal /tmp/cacerts.jks /user/spark/cacerts.jks
sudo -u hdfs /srv/hops/hadoop/bin/hdfs dfs -chown spark /user/spark/cacerts.jks
sudo -u hdfs /srv/hops/hadoop/bin/hdfs dfs -chmod 444 /user/spark/cacerts.jks

echo "All services are up and running!"
sudo /srv/hops/kagent/kagent/bin/status-all-local-services.sh
