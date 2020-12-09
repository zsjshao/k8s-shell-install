### 二进制手动部署
`前提：所有节点已完成docker安装且禁用交换分区`

#### 负载均衡配置

keepalived

```
apt install keepalived haproxy -y
cat > /etc/keepalived/keepalived.conf <<EOF
global_defs {
   notification_email {
     root@zsjshao.com
   }
   notification_email_from keepalived@zsjshao.com
   smtp_server 127.0.0.1
   smtp_connect_timeout 30
   router_id k8s-haproxy01.zsjshao.net
   vrrp_skip_check_adv_addr
#   vrrp_strict
   vrrp_garp_interval 0
   vrrp_gna_interval 0
   vrrp_iptables
}
 
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 80
    priority 100
    advert_int 1
    unicast_src_ip 192.168.3.191
    unicast_peer {
        192.168.3.192
    }
    authentication {
        auth_type PASS
        auth_pass 1122
    }
    virtual_ipaddress {
        192.168.3.200 dev eth0
    }
}
EOF
```

haproxy

```
listen k8s_api_nodes_6443
    bind 192.168.3.200:6443
    mode tcp
    log global
    server 192.168.3.181 192.168.3.181:6443  check inter 3000 fall 2 rise 5
    server 192.168.3.182 192.168.3.182:6443  check inter 3000 fall 2 rise 5
    server 192.168.3.183 192.168.3.183:6443  check inter 3000 fall 2 rise 5

listen k8s_api_etcd_2379
    bind 192.168.3.200:2379
    mode tcp
    log global
    server 192.168.3.186 192.168.3.186:2379  check inter 3000 fall 2 rise 5
    server 192.168.3.187 192.168.3.187:2379  check inter 3000 fall 2 rise 5
    server 192.168.3.188 192.168.3.188:2379  check inter 3000 fall 2 rise 5
```

#### 域名解析

```
192.168.3.200  kubernetes-api.zsjshao.net
192.168.3.200  etcd.zsjshao.net
```

`使用haproxy进行反代`

#### 下载etcd安装包

```
wget https://github.com/etcd-io/etcd/releases/download/v3.4.6/etcd-v3.4.6-linux-amd64.tar.gz
mkdir /tmp/bin/ -p
tar xf etcd-v3.4.6-linux-amd64.tar.gz
cp etcd-v3.4.6-linux-amd64/etcd /tmp/bin/
cp etcd-v3.4.6-linux-amd64/etcdctl /tmp/bin/
```

#### 下载kubernetes二进制包

```
wget https://dl.k8s.io/v1.18.0/kubernetes-server-linux-amd64.tar.gz
tar xf kubernetes-server-linux-amd64.tar.gz
rm -rf kubernetes/server/bin/*.tar
rm -rf kubernetes/server/bin/*_tag
cp kubernetes/server/bin/* /tmp/bin
```

下载CNI插件

```
wget https://github.com/containernetworking/plugins/releases/download/v0.8.5/cni-plugins-linux-amd64-v0.8.5.tgz
mkdir /tmp/cni/ -p
tar xf cni-plugins-linux-amd64-v0.8.5.tgz -C /tmp/cni/
```

下载安装脚本

```
wget http://www.zsjshao.net:9999/zsjshao/k8s-shell-install/archive/master.tar.gz
tar xf master.tar.gz
root@k8s-master01:~# tree .
.
├── 00-env.sh
├── 01-prepare.sh
├── 02-etcd.sh
├── 03-kube-master.sh
├── 04-kube-node.sh
```

`修改00-env.sh环境配置文件，依次执行01-prepare.sh、02-etcd.sh、03-kube-master.sh、04-kube-node.sh`

安装flannel

```
vim kube-flannel.yml
...
  net-conf.json: |
    {
      "Network": "172.20.0.0/16",
      "Backend": {
        "Type": "vxlan"
        "Directrouting": "true"
      }
    }
kubectl apply -f kube-flannel.yml
```

安装coredns

```
bash deploy.sh -i 10.68.0.10 -r "10.68.0.0/16" -s -t coredns.yaml.sed | kubectl apply -f -
```

安装calico

```
vim canal.yaml
...
  net-conf.json: |
    {
      "Network": "172.20.0.0/16",
      "Backend": {
        "Type": "vxlan"
        "Directrouting": "true"
      }
    }
kubectl apply -f canal.yaml
```

查看集群状态

```
root@k8s-master01:~# kubectl get nodes
NAME            STATUS   ROLES    AGE   VERSION
192.168.3.181   Ready    <none>   22m   v1.18.0
192.168.3.182   Ready    <none>   22m   v1.18.0
192.168.3.183   Ready    <none>   22m   v1.18.0
192.168.3.189   Ready    <none>   22m   v1.18.0
192.168.3.190   Ready    <none>   22m   v1.18.0
```

