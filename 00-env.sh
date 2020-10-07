# k8s cluster env
#前提环境需求
# 配置haproxy反代master节点
# 解析kubernetes-api.${OrganizationName:-zsjshao.net}域名至haproxy反代地址

# 配置haproxy反代etcd
# 解析etcd${OrganizationName:-zsjshao.net}域名至haproxy反代地址

MASTER_MEMBERS="192.168.3.181,192.168.3.182,192.168.3.183"     #master节点IP，格式IP,IP，可动态添加，后期添加master直接在原有IP基础上添加IP，然后执行03-kube-master.sh
NODE_MEMBERS="192.168.3.189,192.168.3.190"                     #node节点IP，格式IP,IP，可动态添加，后期添加note直接在原有IP基础上添加IP，然后执行04-kube-node.sh
ETCD_MEMBERS="192.168.3.186,192.168.3.187,192.168.3.188"       #etcd节点IP，不可动态调整
IP_RANGES="10.68.0.0/16"                                       #SVC IP地址段
CLUSTER_CIDR="172.20.0.0/16"                                   #pod地址段
PORT_RANGES="20000-40000"                                      #端口范围
CLUSTER_DNS_DOMAIN="cluster.local"                             #域

CNITEMPDIR="/tmp/cni/"                   #cni插件解压后的二进制文件存放位置
BINTEMPDIR="/tmp/bin/"                   #将server包解压后的二进制文件存放位置，包括etcd和etcdctl二进制文件

TEMPDIR="/opt/k8s/"                      #部署文件临时存储位置
DDIR="/usr/local/k8s/"                   #目标主机k8s文件存储位置

OrganizationName=zsjshao.net             #证书域名
CountryName=CN                           #国家
ProvinceName=GD                          #省份
OrganizationName=${OrganizationName:-zsjshao.net}    #组织
CITY=GZ                                  #城市
UnitName=devops                          #部门

MASTER_BINTEMPDIR="${BINTEMPDIR}"
NODE_BINTEMPDIR="${BINTEMPDIR}"
ETCD_BINTEMPDIR="${BINTEMPDIR}" 

MASTER_TEMPDIR="${TEMPDIR}master/"
MASTER_CERTTEMPDIR="${MASTER_TEMPDIR}pki/"
MASTER_CONFTEMPDIR="${MASTER_TEMPDIR}conf/"
CA_TEMPDIR="${TEMPDIR}pki/"
ETCD_TEMPDIR="${TEMPDIR}etcd/"
ETCD_CERTTEMPDIR="${ETCD_TEMPDIR}pki/"
ETCD_CONFTEMPDIR="${ETCD_TEMPDIR}conf/"

MASTER_DIR="${DDIR}kube/"
MASTER_CERTDIR="${MASTER_DIR}pki/"
MASTER_BINDIR="${MASTER_DIR}bin/"
MASTER_CONFDIR="${MASTER_DIR}conf/"
NODE_KUBELET_DATADIR="${MASTER_DIR}kubelet_data/"
NODE_KUBE_PROXY_DATADIR="${MASTER_DIR}kube-proxy_data/"

ETCDDIR="${DDIR}etcd/"
ETCD_CERTDIR="${ETCDDIR}pki/"
ETCD_CEBINDIR="${ETCDDIR}bin/"
ETCD_DATADIR="${ETCDDIR}data/"

MASTER_NODE_IPS=$(echo ${MASTER_MEMBERS} | tr , ' ')
NODE_NODE_IPS=$(echo ${NODE_MEMBERS} | tr , ' ')
ETCD_NODE_IPS=$(echo ${ETCD_MEMBERS} | tr , ' ')
CLUSTER_SERVICE_IP=$(echo ${IP_RANGES} | awk -F\" "{print $2}" | awk -F\. -v OFS="." '{print $1,$2,$3}').1
CLUSTER_DNS_IP=$(echo ${IP_RANGES} | awk -F\" "{print $2}" | awk -F\. -v OFS="." '{print $1,$2,$3}').10

ETCDINDEX=1
for NODE_IP in ${ETCD_NODE_IPS} ; do
if [ ${ETCDINDEX} == 1 ] ; then
  ETCD_CLUSTER=etcd0${ETCDINDEX}=https://${NODE_IP}:2380
  ETCD_CLUSTER_API=https://${NODE_IP}:2379
else
  ETCD_CLUSTER=${ETCD_CLUSTER},etcd0${ETCDINDEX}=https://${NODE_IP}:2380
  ETCD_CLUSTER_API=${ETCD_CLUSTER_API},https://${NODE_IP}:2379
fi
let ETCDINDEX++
done

function openssl_sign() {
  SUBJECT="/C=${CountryName}/ST=${ProvinceName}/L=${CITY}/O=${2}/OU=${UnitName}/CN=${3}"
  [ -f ${1}.${OrganizationName}.crt ] || openssl genrsa -out ${1}.${OrganizationName}.key 4096
  [ -f ${1}.${OrganizationName}.crt ] || openssl req -sha512 -new -subj "${SUBJECT}" -key ${1}.${OrganizationName}.key -out ${1}.${OrganizationName}.csr
  [ -f ${1}.${OrganizationName}.crt ] || openssl x509 -req -sha512 -days 36500 -extfile ${4} -CA ${CA_TEMPDIR}${OrganizationName}-ca.crt -CAkey ${CA_TEMPDIR}${OrganizationName}-ca.key -CAcreateserial -in ${1}.${OrganizationName}.csr -out ${1}.${OrganizationName}.crt
  \rm -f *.csr
}

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