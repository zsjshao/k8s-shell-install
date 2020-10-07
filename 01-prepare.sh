#!/bin/sh
source 00-env.sh

touch /root/.rnd

if [ ! -f ${CA_TEMPDIR}${OrganizationName}-ca.crt ] ; then
  mkdir ${CA_TEMPDIR} -p
  SUBJECT="/C=${CountryName}/ST=${ProvinceName}/L=${CITY}/O=${OrganizationName}/OU=${UnitName}/CN=${OrganizationName}"
  openssl genrsa -out ${CA_TEMPDIR}${OrganizationName}-ca.key 4096
  openssl req -x509 -new -nodes -sha512 -days 36500 -subj "${SUBJECT}" -key ${CA_TEMPDIR}${OrganizationName}-ca.key -out ${CA_TEMPDIR}${OrganizationName}-ca.crt
fi

mkdir ${ETCD_BINTEMPDIR} ${ETCD_CERTTEMPDIR} ${ETCD_CONFTEMPDIR} ${MASTER_BINTEMPDIR} ${MASTER_CONFTEMPDIR} ${MASTER_CERTTEMPDIR} ${NODE_KUBE-PROXY_DATADIR} -p

cd ${ETCD_CERTTEMPDIR}

cat > ${CA_TEMPDIR}client.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = clientAuth
EOF

openssl_sign client ${OrganizationName} client.${OrganizationName} ${CA_TEMPDIR}client.ext

openssl_sign admin system:masters admin.${OrganizationName} ${CA_TEMPDIR}client.ext

openssl_sign controller ${OrganizationName} system:kube-controller-manager ${CA_TEMPDIR}client.ext
openssl_sign scheduler ${OrganizationName} system:kube-scheduler ${CA_TEMPDIR}client.ext
openssl_sign proxy ${OrganizationName} system:kube-proxy ${CA_TEMPDIR}client.ext

cat > ${CA_TEMPDIR}etcd-peer.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1=*.${OrganizationName}
DNS.2=localhost
IP.1=127.0.0.1
IP.2=0:0:0:0:0:0:0:1
EOF

CERTINDEX=3

for NODE_IP in ${ETCD_NODE_IPS} ; do
  echo IP.${CERTINDEX}=$NODE_IP >> ${CA_TEMPDIR}etcd-peer.ext
  let CERTINDEX++
done

openssl_sign etcd_peer ${OrganizationName} etcd.${OrganizationName} ${CA_TEMPDIR}etcd-peer.ext
openssl_sign etcd_server ${OrganizationName} etcd.${OrganizationName} ${CA_TEMPDIR}etcd-peer.ext

cp -f ${CA_TEMPDIR}${OrganizationName}* ${ETCD_CERTTEMPDIR}
cd ${MASTER_CERTTEMPDIR}

cat > ${CA_TEMPDIR}apiserver.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1=${OrganizationName}
DNS.2=*.${OrganizationName}
DNS.3=kubernetes
DNS.4=kubernetes.svc
DNS.5=kubernetes.svc.cluster
DNS.6=kubernetes.svc.${CLUSTER_DNS_DOMAIN}
IP.1=${CLUSTER_SERVICE_IP}
EOF

openssl_sign kubernetes-api ${OrganizationName} kubernetes-api.${OrganizationName} ${CA_TEMPDIR}apiserver.ext

cp -f ${CA_TEMPDIR}${OrganizationName}-ca.key ${MASTER_CERTTEMPDIR}
cp -f ${CA_TEMPDIR}${OrganizationName}-ca.crt ${MASTER_CERTTEMPDIR}
cp -f ${ETCD_CERTTEMPDIR}* ${MASTER_CERTTEMPDIR}
