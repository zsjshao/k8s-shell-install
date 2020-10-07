#!/bin/sh
source 00-env.sh

if [ ! -f ${MASTER_BINTEMPDIR}kube-apiserver ] ; then
  echo no file ${MASTER_BINTEMPDIR}kube-apiserver
  exit 1
fi

for master_node_ip in ${MASTER_NODE_IPS} ; do

cd ${MASTER_CONFTEMPDIR}
cat > ${master_node_ip}.apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
ExecStart=${MASTER_BINDIR}kube-apiserver \\
  --advertise-address=${master_node_ip} \\
  --allow-privileged=true \\
  --enable-aggregator-routing=true \\
  --anonymous-auth=false \\
  --authorization-mode=Node,RBAC \\
  --bind-address=${master_node_ip} \\
  --client-ca-file=${MASTER_CERTDIR}${OrganizationName}-ca.crt \\
  --etcd-cafile=${MASTER_CERTDIR}${OrganizationName}-ca.crt \\
  --etcd-certfile=${MASTER_CERTDIR}admin.${OrganizationName}.crt \\
  --etcd-keyfile=${MASTER_CERTDIR}admin.${OrganizationName}.key \\
  --etcd-servers=${ETCD_CLUSTER_API} \\
  --kubelet-certificate-authority=${MASTER_CERTDIR}${OrganizationName}-ca.crt \\
  --kubelet-client-certificate=${MASTER_CERTDIR}admin.${OrganizationName}.crt \\
  --kubelet-client-key=${MASTER_CERTDIR}admin.${OrganizationName}.key \\
  --kubelet-https=true \\
  --tls-cert-file=${MASTER_CERTDIR}kubernetes-api.${OrganizationName}.crt \\
  --tls-private-key-file=${MASTER_CERTDIR}kubernetes-api.${OrganizationName}.key \\
  --proxy-client-cert-file=${MASTER_CERTDIR}client.${OrganizationName}.crt \\
  --proxy-client-key-file=${MASTER_CERTDIR}client.${OrganizationName}.key \\
  --requestheader-allowed-names= \\
  --requestheader-client-ca-file=${MASTER_CERTDIR}${OrganizationName}-ca.crt \\
  --requestheader-extra-headers-prefix=X-Remote-Extra- \\
  --requestheader-group-headers=X-Remote-Group \\
  --requestheader-username-headers=X-Remote-User \\
  --service-account-key-file=${MASTER_CERTDIR}${OrganizationName}-ca.key \\
  --service-cluster-ip-range=${IP_RANGES} \\
  --service-node-port-range=${PORT_RANGES} \\
  --endpoint-reconciler-type=lease \\
  --logtostderr=true \\
  --v=2
Restart=always
RestartSec=5
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

#  --etcd-servers=${ETCD_CLUSTER_API} \\
#--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname 

cat > ${master_node_ip}.controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=${MASTER_BINDIR}kube-controller-manager \\
  --address=127.0.0.1 \\
  --allocate-node-cidrs=true \\
  --cluster-cidr=${CLUSTER_CIDR} \\
  --cluster-name=${OrganizationName} \\
  --cluster-signing-cert-file=${MASTER_CERTDIR}${OrganizationName}-ca.crt \\
  --cluster-signing-key-file=${MASTER_CERTDIR}${OrganizationName}-ca.key \\
  --kubeconfig=${MASTER_CONFDIR}kube-controller-manager.conf \\
  --leader-elect=true \\
  --node-cidr-mask-size=24 \\
  --root-ca-file=${MASTER_CERTDIR}${OrganizationName}-ca.crt \\
  --service-account-private-key-file=${MASTER_CERTDIR}${OrganizationName}-ca.key \\
  --service-cluster-ip-range=${IP_RANGES} \\
  --use-service-account-credentials=true \\
  --v=2
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > ${master_node_ip}.scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=${MASTER_BINDIR}kube-scheduler \\
  --address=127.0.0.1 \\
  --kubeconfig=${MASTER_CONFDIR}kube-scheduler.conf \\
  --leader-elect=true \\
  --v=2
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

k8s_cfg admin admin admin
k8s_cfg kube-controller-manager controller system:kube-controller-manager
k8s_cfg kube-scheduler scheduler system:kube-scheduler

ssh ${master_node_ip} "mkdir ${MASTER_BINDIR} ${MASTER_CONFDIR} ${MASTER_CERTDIR} /root/.kube -p"
ssh ${master_node_ip} "ln -s ${MASTER_BINDIR}kubectl /usr/bin/"
rsync -avlogp ${MASTER_BINTEMPDIR} ${master_node_ip}:${MASTER_BINDIR}
cd ${MASTER_CERTTEMPDIR}
rsync -avlogp admin* client* controller* etcd* kubernetes-api* proxy* scheduler* ${OrganizationName}* ${master_node_ip}:${MASTER_CERTDIR}
cd ${MASTER_CONFTEMPDIR}
rsync -avlogp ${MASTER_CONFTEMPDIR}admin.conf ${master_node_ip}:/root/.kube/config
rsync -avlogp kube-scheduler.conf kube-controller-manager.conf ${master_node_ip}:${MASTER_CONFDIR}
rsync -avlogp ${MASTER_CONFTEMPDIR}${master_node_ip}.apiserver.service ${master_node_ip}:/lib/systemd/system/kube-apiserver.service
rsync -avlogp ${MASTER_CONFTEMPDIR}${master_node_ip}.controller-manager.service ${master_node_ip}:/lib/systemd/system/kube-controller-manager.service
rsync -avlogp ${MASTER_CONFTEMPDIR}${master_node_ip}.scheduler.service ${master_node_ip}:/lib/systemd/system/kube-scheduler.service

ssh ${master_node_ip} "systemctl daemon-reload"
ssh ${master_node_ip} "systemctl enable kube-apiserver kube-controller-manager kube-scheduler"
done

for master_node_ip in ${MASTER_NODE_IPS} ; do
ssh ${master_node_ip} "systemctl restart kube-apiserver kube-controller-manager kube-scheduler"
ssh ${master_node_ip} "kubectl label node ${master_node_ip} kubernetes.io/role=master --overwrite"
#node-role.kubernetes.io/master:NoSchedule
done