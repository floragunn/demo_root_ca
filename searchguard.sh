#!/bin/bash
#set -x

post_slack() {
   curl -X POST --data-urlencode 'payload={"channel": "#aws_notify", "username": "awsbot", "text": "'"$1"'", "icon_emoji": ":cyclone:"}' $SLACKURL > /dev/null 2>&1
}

do_install() {
  
  export REGION=$(wget -qO- http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//' | tr -d '"')
  export STACKNAME=$(aws ec2 describe-instances --filters "Name=ip-address,Values=$(ec2metadata --public-ipv4)" --region $REGION | jq '.Reservations[0].Instances[0].Tags | map(select (.Key == "aws:cloudformation:stack-name" )) ' | jq .[0].Value | tr -d '"')
  SG_PUBHOST=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)
  SG_PRIVHOST=$(curl -s http://169.254.169.254/latest/meta-data/hostname)
  post_slack "Will bootstrap $STACKNAME in $REGION on $SG_PUBHOST ($DIST)"
  
  #GITHUB_URL="$(aws cloudformation describe-stacks --stack-name $STACKNAME  --region $REGION | jq '.Stacks[0].Parameters | map(select (.ParameterKey == "GithubUrl" ))[0].ParameterValue' | tr -d '"' )"
  
  systemctl stop kibana.service
  systemctl stop metricbeat.service
  systemctl stop elasticsearch.service
  
  
  ES_VERSION=5.0.0
  
  if [ ! -f "elasticsearch-$ES_VERSION.deb" ]; then
    wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$ES_VERSION.deb > /dev/null 2>&1
    check_ret
  fi
  
  dpkg --force-all -i elasticsearch-$ES_VERSION.deb > /dev/null
  check_ret
  
  wget https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-$ES_VERSION-amd64.deb > /dev/null 2>&1
  check_ret
  
  dpkg --force-all -i metricbeat-$ES_VERSION-amd64.deb > /dev/null
  check_ret
  
  wget https://artifacts.elastic.co/downloads/kibana/kibana-$ES_VERSION-amd64.deb > /dev/null 2>&1
  check_ret
  
  dpkg --force-all -i kibana-$ES_VERSION-amd64.deb > /dev/null
  check_ret
  
  NETTY_NATIVE_VERSION=1.1.33.Fork23
  NETTY_NATIVE_CLASSIFIER=linux-x86_64
  ES_BIN=/usr/share/elasticsearch/bin
  ES_CONF=/etc/elasticsearch
  ES_LOG=/var/log/elasticsearch
  ES_PLUGINS=/usr/share/elasticsearch/plugins
  SG_VERSION=5.0.0-8
  ORG_NAME="Example DSG Inc. 1.0"
  
  echo "SG_PUBHOST: $SG_PUBHOST"
  echo "SG_PRIVHOST: $SG_PRIVHOST"
  
  $ES_BIN/elasticsearch-plugin remove discovery-ec2 > /dev/null 2>&1
  $ES_BIN/elasticsearch-plugin remove search-guard-5 > /dev/null 2>&1
  
  $ES_BIN/elasticsearch-plugin install -b discovery-ec2
  check_ret
  $ES_BIN/elasticsearch-plugin install -b com.floragunn:search-guard-5:$SG_VERSION
  check_ret
  
  cd demo_root_ca
  git pull > /dev/null 2>&1
  
  ./gen_node_cert.sh "$ORG_NAME" "CN=$SG_PUBHOST" "$SG_PUBHOST" changeit "ca pass" > /dev/null 2>&1
  check_ret
  ./gen_node_cert.sh "$ORG_NAME" "CN=$SG_PRIVHOST" "$SG_PRIVHOST" changeit "ca pass" > /dev/null 2>&1
  check_ret
  ./gen_client_node_cert.sh "$ORG_NAME" "CN=user" changeit "ca pass" > /dev/null 2>&1
  check_ret
  ./gen_client_node_cert.sh "$ORG_NAME" "CN=sgadmin" changeit "ca pass" > /dev/null 2>&1
  check_ret
  ./gen_nonsgserver_certificate.sh "$ORG_NAME" "/C=DE/ST=Berlin/L=City/O=floragunn/OU=IT Department/CN=topbeat" $SG_PUBHOST topbeat "ca pass"  > /dev/null 2>&1
  check_ret
  ./gen_nonsgserver_certificate.sh "$ORG_NAME" "/C=DE/ST=Berlin/L=City/O=floragunn/OU=IT Department/CN=kibana" $SG_PUBHOST kibana "ca pass"  > /dev/null 2>&1
  check_ret

  cp *.jks $ES_CONF/
  cp *.pem $ES_CONF/
  cp *.key $ES_CONF/
  cp ca/*.pem $ES_CONF/

  #chown elasticsearch:elasticsearch $ES_CONF/*
  
  if [ ! -f "netty-tcnative-$NETTY_NATIVE_VERSION-$NETTY_NATIVE_CLASSIFIER.jar" ]; then
    echo "Download netty native"
    wget -O $ES_PLUGINS/search-guard-5/netty-tcnative-$NETTY_NATIVE_VERSION-$NETTY_NATIVE_CLASSIFIER.jar https://search.maven.org/remotecontent?filepath=io/netty/netty-tcnative/$NETTY_NATIVE_VERSION/netty-tcnative-$NETTY_NATIVE_VERSION-$NETTY_NATIVE_CLASSIFIER.jar
    check_ret
  fi
  
  cd - > /dev/null 2>&1
  
  cd $ES_PLUGINS/search-guard-5
   
  wget "http://oss.sonatype.org/service/local/artifact/maven/content?c=jar-with-dependencies&r=releases&g=com.floragunn&a=dlic-search-guard-authbackend-ldap&v=5.0-4" --content-disposition  > /dev/null 2>&1
  check_ret
  wget "http://oss.sonatype.org/service/local/artifact/maven/content?c=jar-with-dependencies&r=releases&g=com.floragunn&a=dlic-search-guard-module-auditlog&v=5.0-3" --content-disposition  > /dev/null 2>&1
  check_ret
  wget "http://oss.sonatype.org/service/local/artifact/maven/content?c=jar-with-dependencies&r=releases&g=com.floragunn&a=dlic-search-guard-rest-api&v=5.0-1" --content-disposition  > /dev/null 2>&1
  check_ret
  wget "http://oss.sonatype.org/service/local/artifact/maven/content?c=jar-with-dependencies&r=releases&g=com.floragunn&a=dlic-search-guard-auth-http-kerberos&v=5.0-2" --content-disposition  > /dev/null 2>&1
  check_ret
  wget "http://oss.sonatype.org/service/local/artifact/maven/content?c=jar-with-dependencies&r=releases&g=com.floragunn&a=dlic-search-guard-auth-http-jwt&v=5.0-2" --content-disposition  > /dev/null 2>&1
  check_ret
  wget "http://oss.sonatype.org/service/local/artifact/maven/content?c=jar-with-dependencies&r=releases&g=com.floragunn&a=dlic-search-guard-module-dlsfls&v=5.0-4" --content-disposition  > /dev/null 2>&1
  check_ret
  cd - > /dev/null 2>&1
  
  echo "cluster.name: $STACKNAME" > $ES_CONF/elasticsearch.yml
  echo "discovery.type: ec2" >> $ES_CONF/elasticsearch.yml
  echo "discovery.ec2.host_type: private_dns" >> $ES_CONF/elasticsearch.yml
  echo "cloud.aws.protocol: http" >> $ES_CONF/elasticsearch.yml
  #echo 'network.host: ["_ec2:publicDns_"]' >> $ES_CONF/elasticsearch.yml
  echo "transport.host: $SG_PRIVHOST" >> $ES_CONF/elasticsearch.yml
  echo "transport.tcp.port: 9300" >> $ES_CONF/elasticsearch.yml
  
  echo "http.host: $SG_PUBHOST" >> $ES_CONF/elasticsearch.yml
  echo "http.port: 9200" >> $ES_CONF/elasticsearch.yml
  echo "http.cors.enabled: true" >> $ES_CONF/elasticsearch.yml
  #echo "http.cors.allow-origin: *" >> $ES_CONF/elasticsearch.yml
  echo "cloud.aws.region: $REGION" >> $ES_CONF/elasticsearch.yml
  
  echo "cluster.routing.allocation.disk.watermark.high: 10mb" >> $ES_CONF/elasticsearch.yml
  echo "cluster.routing.allocation.disk.watermark.low: 10mb" >> $ES_CONF/elasticsearch.yml
  echo "node.name: $SG_PUBHOST" >> $ES_CONF/elasticsearch.yml
  echo "" >> $ES_CONF/elasticsearch.yml
  echo "" >> $ES_CONF/elasticsearch.yml
  echo "##################################################" >> $ES_CONF/elasticsearch.yml
  echo "#          Search Guard 5 configuration          " >> $ES_CONF/elasticsearch.yml
  echo "#                                                " >> $ES_CONF/elasticsearch.yml
  echo "#Host: $SG_PUBHOST    $SG_PRIVHOST               " >> $ES_CONF/elasticsearch.yml
  echo "#Generated: $(date)                              " >> $ES_CONF/elasticsearch.yml
  echo "#ES-Version: $ES_VERSION                         " >> $ES_CONF/elasticsearch.yml
  echo "#SG-Version: $SG_VERSION                         " >> $ES_CONF/elasticsearch.yml
  echo "#NettyNative-Version: $NETTY_NATIVE_VERSION      " >> $ES_CONF/elasticsearch.yml
  echo "#                                                " >> $ES_CONF/elasticsearch.yml
  echo "##################################################" >> $ES_CONF/elasticsearch.yml	
  echo "searchguard.ssl.transport.enabled: true" >> $ES_CONF/elasticsearch.yml
  echo "searchguard.ssl.transport.keystore_filepath: CN=$SG_PRIVHOST-keystore.jks" >> $ES_CONF/elasticsearch.yml
  #echo "searchguard.ssl.transport.keystore_password: $KS_PASS" >> $ES_CONF/elasticsearch.yml
  echo "searchguard.ssl.transport.truststore_filepath: truststore.jks" >> $ES_CONF/elasticsearch.yml
  #echo "searchguard.ssl.transport.truststore_password: $TS_PASS" >> $ES_CONF/elasticsearch.yml
  #echo "searchguard.ssl.transport.enforce_hostname_verification: false" >> $ES_CONF/elasticsearch.yml

  echo "searchguard.ssl.http.enabled: true" >> $ES_CONF/elasticsearch.yml
  echo "searchguard.ssl.http.keystore_filepath: CN=$SG_PUBHOST-keystore.jks" >> $ES_CONF/elasticsearch.yml
  #echo "searchguard.ssl.http.keystore_password: $KS_PASS" >> $ES_CONF/elasticsearch.yml
  echo "searchguard.ssl.http.truststore_filepath: truststore.jks" >> $ES_CONF/elasticsearch.yml
  #echo "searchguard.ssl.http.truststore_password: $TS_PASS" >> $ES_CONF/elasticsearch.yml

  #echo "searchguard.kerberos.krb5_filepath: /Users/temp/kerberos_ldap_environment/krb5.conf" >> $ES_CONF/elasticsearch.yml
  #echo "searchguard.kerberos.acceptor_keytab_filepath: http_srv.keytab" >> $ES_CONF/elasticsearch.yml
  echo "searchguard.audit.type: internal_elasticsearch" >> $ES_CONF/elasticsearch.yml

  echo "searchguard.authcz.admin_dn:">> $ES_CONF/elasticsearch.yml
  echo "  - CN=sgadmin" >> $ES_CONF/elasticsearch.yml

  echo "vm.max_map_count=262144" >> /etc/sysctl.conf
  echo 262144 > /proc/sys/vm/max_map_count 
    
  /bin/systemctl daemon-reload
  check_ret
  /bin/systemctl enable elasticsearch.service
  check_ret
  systemctl start elasticsearch.service
  check_ret
  
  while ! nc -z $SG_PUBHOST 9200 > /dev/null 2>&1; do
    echo "Wait for elasticsearch ..."
    sleep 0.5
  done
  
  echo "elasticsearch up"
  sleep 5
  
  post_slack "run sgadmin $SG_PUBHOST $SG_PRIVHOST"
  
  chmod +x $ES_PLUGINS/search-guard-5/tools/sgadmin.sh
  $ES_PLUGINS/search-guard-5/tools/sgadmin.sh -cd $ES_PLUGINS/search-guard-5/sgconfig -h $SG_PRIVHOST -icl -ts $ES_CONF/truststore.jks -ks $ES_CONF/CN=$SG_PRIVHOST-keystore.jks
  check_ret
  post_slack "SG $SG_VERSION initialized on https://$SG_PUBHOST:9200"

  cat demo_root_ca/kibana/kibana.yml | sed -e "s/RPLC_HOST/$SG_PUBHOST/g" > /etc/kibana/kibana.yml 
    
  /bin/systemctl enable kibana.service
  check_ret
  systemctl start kibana.service  
  check_ret
  
  cat demo_root_ca/metricbeat/metricbeat.yml | sed -e "s/RPLC_HOST/$SG_PUBHOST/g" > /etc/metricbeat/metricbeat.yml

  /bin/systemctl enable metricbeat.service
  check_ret
  systemctl start metricbeat.service
  check_ret
}


show_info() {
  do_log "This script will bootstrap Search Guard $SG_VERSION"
  do_log "It is supposed to be run on an Ubuntu AWS instance"
  do_log "Detect OS: $DIST"
  do_log ""
}

do_log() {
  echo "$1" 1>&2
}

do_error_exit() {
  echo "ERR: $1" 1>&2
  post_slack "ERR: $1"
  exit 1
}

check_prerequisites() {

  if ! check_cmd apt-get; then
    do_error_exit "apt-get is not installed (not ubuntu?)"
  fi
  
  
  ########## start Oracle 8 Java 
  apt-get -yqq update > /dev/null 2>&1
  echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections > /dev/null 2>&1
  apt-get -yqq install software-properties-common > /dev/null 2>&1
  add-apt-repository -y ppa:webupd8team/java > /dev/null 2>&1
  apt-get -yqq update > /dev/null 2>&1
  apt-get -yqq install oracle-java8-installer oracle-java8-unlimited-jce-policy > /dev/null 2>&1
  ########## end Oracle 8 Java

  apt-get -yqq install ntp ntpdate haveged libssl-dev autoconf libtool build-essential libffi6 libffi-dev git curl wget openssl libapr1 iputils-ping dnsutils host netcat telnet > /dev/null 2>&1

  wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
  echo "deb https://artifacts.elastic.co/packages/5.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-5.x.list
  apt-get -yqq update
  apt-get -yqq install unzip awscli docker.io curl git jq ansible apt-transport-https

  if ! check_cmd docker; then
    do_error_exit "docker is not installed"
  fi
  
  if ! check_cmd curl; then
    do_error_exit "curl is not installed"
  fi
  
  if ! check_cmd git; then
    do_error_exit "git is not installed"
  fi
  
  if ! check_cmd unzip; then
    do_error_exit "unzip is not installed"
  fi
  
  if ! check_cmd ansible; then
    do_error_exit "ansible is not installed"
  fi
  
  if ! check_cmd aws; then
    do_error_exit "aws is not installed"
  fi
  
  if ! check_cmd jq; then
    do_error_exit "jq is not installed"
  fi
  
  if ! check_cmd java; then
    do_error_exit "java is not installed"
  fi
  
  if ! check_cmd openssl; then
    do_error_exit "openssl is not installed"
  fi
  
  echo "- prerequisites ok"
}

check_root() {
  if [ "$(id -u)" != "0" ]; then
   do_error_exit "This script must be run as root"
  fi
}

check_cmd() {
  if command -v $1 >/dev/null 2>&1
  then
    return 0
  else
    return 1
  fi
}

check_aws() {
   #http://stackoverflow.com/questions/6475374/how-do-i-make-cloud-init-startup-scripts-run-every-time-my-ec2-instance-boots
   #curl http://169.254.169.254/latest/user-data
  INSTANCE_ID_OK=$(curl --max-time 5 -s -o /dev/null -I -w "%{http_code}" http://169.254.169.254/latest/meta-data/instance-id)
  if [ "$INSTANCE_ID_OK" != "200" ]; then
   do_error_exit "This script must be run within AWS ($INSTANCE_ID_OK)"
  fi
}

check_ret() {
    local status=$?
    if [ $status -ne 0 ]; then
         echo "ERR - The last command failed with status $status" 1>&2
         post_slack "ERR - The last command failed with status $status"
         exit $status
    fi
}

cd /

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DIST=`grep DISTRIB_ID /etc/*-release | awk -F '=' '{print $2}'`
echo $(date) >> /root/runs

check_root
check_aws
show_info
check_prerequisites
do_install
