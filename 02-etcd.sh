#!/bin/sh
source 00-env.sh

if [ ! -f ${ETCD_BINTEMPDIR}etcd ] ; then
  echo no file ${ETCD_BINTEMPDIR}etcd
  exit 1
fi

cd ${ETCD_CONFTEMPDIR}

ETCDNODEINDEX=1
for NODE_IP in ${ETCD_NODE_IPS} ; do
  ping -c 1 -w 1 ${NODE_IP} || break

cat > ${NODE_IP}.service <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
WorkingDirectory=${ETCD_DATADIR}
ExecStart=${ETCD_CEBINDIR}etcd \\
  --name=etcd0${ETCDNODEINDEX} \\
  --data-dir=${ETCD_DATADIR} \\
  --advertise-client-urls=https://${NODE_IP}:2379 \\
  --listen-client-urls=https://${NODE_IP}:2379,https://127.0.0.1:2379 \\
  --initial-advertise-peer-urls=https://${NODE_IP}:2380 \\
  --listen-peer-urls=https://${NODE_IP}:2380 \\
  --cert-file=${ETCD_CERTDIR}etcd_server.${OrganizationName}.crt \\
  --key-file=${ETCD_CERTDIR}etcd_server.${OrganizationName}.key \\
  --trusted-ca-file=${ETCD_CERTDIR}${OrganizationName}-ca.crt \\
  --peer-cert-file=${ETCD_CERTDIR}etcd_peer.${OrganizationName}.crt \\
  --peer-key-file=${ETCD_CERTDIR}etcd_peer.${OrganizationName}.key \\
  --peer-trusted-ca-file=${ETCD_CERTDIR}${OrganizationName}-ca.crt \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=${ETCD_CLUSTER} \\
  --initial-cluster-state=new \\
  --snapshot-count=50000 \\
  --auto-compaction-retention=1 \\
  --max-request-bytes=10485760 \\
  --quota-backend-bytes=8589934592
Restart=always
RestartSec=15
LimitNOFILE=65536
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF

let ETCDNODEINDEX++
ssh ${NODE_IP} "mkdir ${ETCD_CERTDIR} ${ETCD_CEBINDIR} ${ETCD_DATADIR} -p"
cd ${ETCD_CERTTEMPDIR}
rsync -avlogp etcd_server.${OrganizationName}.* etcd_peer.${OrganizationName}.* ${CA_TEMPDIR}${OrganizationName}-ca.* ${NODE_IP}:${ETCD_CERTDIR}
rsync -avlogp ${ETCD_CONFTEMPDIR}${NODE_IP}.service ${NODE_IP}:/lib/systemd/system/etcd.service
rsync -avlogp ${ETCD_BINTEMPDIR}etcd ${ETCD_BINTEMPDIR}etcdctl ${NODE_IP}:${ETCD_CEBINDIR}
ssh ${NODE_IP} "systemctl daemon-reload"
ssh ${NODE_IP} "systemctl enable etcd"
ssh ${NODE_IP} "systemctl restart etcd" &
done