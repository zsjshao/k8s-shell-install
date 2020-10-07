#!/bin/sh
source 00-env.sh

if [ ! -f ${NODE_BINTEMPDIR}kubelet ] ; then
  echo no file ${NODE_BINTEMPDIR}kubelet
  exit 1
fi

cd ${MASTER_CONFTEMPDIR}

for node_node_ip in ${NODE_NODE_IPS} ${MASTER_NODE_IPS} ; do

cd ${MASTER_CERTTEMPDIR}

cat > node.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1=${OrganizationName}
DNS.2=*.${OrganizationName}
IP.1=${node_node_ip}
EOF

openssl_sign kubelet${node_node_ip} system:nodes system:node:${node_node_ip} node.ext

cd ${MASTER_CONFTEMPDIR}
cat > ${node_node_ip}.kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
WorkingDirectory=${NODE_KUBELET_DATADIR}
ExecStartPre=/bin/mount -o remount,rw '/sys/fs/cgroup'
ExecStartPre=/bin/mkdir -p /sys/fs/cgroup/cpuset/system.slice/kubelet.service
ExecStartPre=/bin/mkdir -p /sys/fs/cgroup/hugetlb/system.slice/kubelet.service
ExecStartPre=/bin/mkdir -p /sys/fs/cgroup/memory/system.slice/kubelet.service
ExecStartPre=/bin/mkdir -p /sys/fs/cgroup/pids/system.slice/kubelet.service
ExecStart=${MASTER_BINDIR}kubelet \\
  --config=${MASTER_CONFDIR}config${node_node_ip}.yaml \\
  --cni-bin-dir=${MASTER_BINDIR} \\
  --cni-conf-dir=/etc/cni/net.d/ \\
  --hostname-override=${node_node_ip} \\
  --kubeconfig=${MASTER_CONFDIR}kubelet${node_node_ip}.conf \\
  --network-plugin=cni \\
  --pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google_containers/pause-amd64:3.2 \\
  --root-dir=${NODE_KUBELET_DATADIR} \\
  --v=2
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# --cni-conf-dir=/etc/cni/net.d/ 教训，必须是这个目录，不能更改
# --resolv-conf=/run/systemd/resolve/resolv.conf   ubuntu系统
# --resolv-conf=/etc/resolv.conf        centos系统

cat > ${node_node_ip}.proxy.service <<EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
# kube-proxy 根据 --cluster-cidr 判断集群内部和外部流量，指定 --cluster-cidr 或 --masquerade-all 选项后，kube-proxy 会对访问 Service IP 的请求做 SNAT
WorkingDirectory=${NODE_KUBE_PROXY_DATADIR}
ExecStart=${MASTER_BINDIR}kube-proxy \\
  --bind-address=${node_node_ip} \\
  --cluster-cidr=${CLUSTER_CIDR} \\
  --hostname-override=${node_node_ip} \\
  --kubeconfig=${MASTER_CONFDIR}kube-proxy.conf \\
  --logtostderr=true \\
  --proxy-mode=ipvs
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

cat > config${node_node_ip}.yaml <<EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: ${node_node_ip}
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 2m0s
    enabled: true
  x509:
    clientCAFile: ${MASTER_CERTDIR}${OrganizationName}-ca.crt
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m0s
    cacheUnauthorizedTTL: 30s
cgroupDriver: cgroupfs
cgroupsPerQOS: true
clusterDNS:
- ${CLUSTER_DNS_IP}
clusterDomain: ${CLUSTER_DNS_DOMAIN}
configMapAndSecretChangeDetectionStrategy: Watch
containerLogMaxFiles: 3 
containerLogMaxSize: 10Mi
enforceNodeAllocatable:
- pods
eventBurst: 10
eventRecordQPS: 5
evictionHard:
  imagefs.available: 15%
  memory.available: 200Mi
  nodefs.available: 10%
  nodefs.inodesFree: 5%
evictionPressureTransitionPeriod: 5m0s
failSwapOn: true
fileCheckFrequency: 40s
hairpinMode: hairpin-veth 
healthzBindAddress: 127.0.0.1
healthzPort: 10248
httpCheckFrequency: 40s
imageGCHighThresholdPercent: 85
imageGCLowThresholdPercent: 80
imageMinimumGCAge: 2m0s
kubeReservedCgroup: /system.slice/kubelet.service
kubeReserved: {'cpu':'200m','memory':'500Mi','ephemeral-storage':'1Gi'}
kubeAPIBurst: 100
kubeAPIQPS: 50
makeIPTablesUtilChains: true
maxOpenFiles: 1000000
maxPods: 110
nodeLeaseDurationSeconds: 40
nodeStatusReportFrequency: 1m0s
nodeStatusUpdateFrequency: 10s
oomScoreAdj: -999
podPidsLimit: -1
port: 10250
# disable readOnlyPort 
readOnlyPort: 0
resolvConf: /run/systemd/resolve/resolv.conf
runtimeRequestTimeout: 2m0s
serializeImagePulls: true
streamingConnectionIdleTimeout: 4h0m0s
syncFrequency: 1m0s
tlsCertFile: ${MASTER_CERTDIR}kubelet${node_node_ip}.${OrganizationName}.crt
tlsPrivateKeyFile: ${MASTER_CERTDIR}kubelet${node_node_ip}.${OrganizationName}.key
EOF

function k8s_cfg() {
cat > ${1}.conf << EOF
apiVersion: v1
kind: Config
clusters:
- name: ${OrganizationName}
  cluster:
    server: https://kubernetes-api.${OrganizationName}:6443
    certificate-authority-data: $( openssl base64 -A -in ${CA_TEMPDIR}${OrganizationName}-ca.crt ) 
users:
- name: ${3}
  user:
    client-certificate-data: $( openssl base64 -A -in ${MASTER_CERTTEMPDIR}${2}.${OrganizationName}.crt ) 
    client-key-data: $( openssl base64 -A -in ${MASTER_CERTTEMPDIR}${2}.${OrganizationName}.key ) 
contexts:
- context:
    cluster: ${OrganizationName}
    user: ${3}
  name: ${3}@${OrganizationName}
current-context: ${3}@${OrganizationName}
EOF
}

k8s_cfg kubelet${node_node_ip} kubelet${node_node_ip} system:node:${node_node_ip}
k8s_cfg kube-proxy proxy system:kube-proxy

ssh ${node_node_ip} "mkdir ${MASTER_BINDIR} ${MASTER_CONFDIR} ${MASTER_CERTDIR} ${NODE_KUBELET_DATADIR} ${NODE_KUBE_PROXY_DATADIR} -p"
rsync -avlogp ${MASTER_BINTEMPDIR}kubelet ${MASTER_BINTEMPDIR}kube-proxy ${node_node_ip}:${MASTER_BINDIR}
rsync -avlogp ${CNITEMPDIR} ${node_node_ip}:${MASTER_BINDIR}
cd ${MASTER_CERTTEMPDIR}
rsync -avlogp kubelet${node_node_ip}.${OrganizationName}.*  ${OrganizationName}-ca.crt ${node_node_ip}:${MASTER_CERTDIR}

cd ${MASTER_CONFTEMPDIR}
rsync -avlogp kubelet${node_node_ip}.conf kube-proxy.conf ${node_node_ip}:${MASTER_CONFDIR}
rsync -avlogp config${node_node_ip}.yaml ${node_node_ip}:${MASTER_CONFDIR}
rsync -avlogp ${node_node_ip}.proxy.service ${node_node_ip}:/lib/systemd/system/kube-proxy.service
rsync -avlogp ${node_node_ip}.kubelet.service ${node_node_ip}:/lib/systemd/system/kubelet.service
ssh ${node_node_ip} "systemctl daemon-reload"
ssh ${node_node_ip} "systemctl enable kubelet kube-proxy"
ssh ${node_node_ip} "systemctl restart kubelet kube-proxy"
done
