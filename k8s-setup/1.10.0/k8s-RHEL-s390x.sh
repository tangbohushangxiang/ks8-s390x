#!/bin/bash

# Written by yangxiaoxian2011@126.com

# Install kubernetes with kubeadm 1.10.0 on RHEL7.6 s390x
# You need a good network environment.
# Please run this bash on root
# Test passed on LinuxONE Community Cloud

set -e

# Kubernetes version
K8S_VERSION=v1.10.0
K8S_VERSIONN=1.10.0

# Clear firewall rules
echo -e "\n\n********************\nClear firewall rules\n********************\n\n"
iptables -F
echo "Done!"

# Turn off swap
echo -e "\n\n*************\nTurn off swap\n*************\n\n"
swapoff -a
free -h
echo -e "\nDone!"

# Install docker


# Install docker
echo -e "\n\n**************\nInstall docker\n**************\n\n"
yum install -y ebtables ethtool
wget http://ftp.unicamp.br/pub/linuxpatch/s390x/redhat/rhel7.3/docker-17.05.0-ce-rhel7.3-20170523.tar.gz
tar -zxf docker-17.05.0-ce-rhel7.3-20170523.tar.gz
cp ./docker-17.05.0-ce-rhel7.3-20170523/docker* /usr/local/bin
cp ./docker-17.05.0-ce-rhel7.3-20170523/docker* /usr/bin
mkdir -p /data/docker-runtime/
ln -s /data/docker-runtime/ /var/lib/docker
cat << EOF > /usr/lib/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.com
After=network.target
Wants=docker-storage-setup.service
[Service]
Type=notify
EnvironmentFile=-/etc/sysconfig/docker
EnvironmentFile=-/etc/sysconfig/docker-storage
EnvironmentFile=-/etc/sysconfig/docker-network
Environment=GOTRACEBACK=crash
ExecStart=/usr/bin/docker daemon $OPTIONS \
      $DOCKER_STORAGE_OPTIONS \
      $DOCKER_NETWORK_OPTIONS \
      $ADD_REGISTRY \
      $BLOCK_REGISTRY \
      $INSECURE_REGISTRY
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
MountFlags=slave
TimeoutStartSec=1min
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl disable docker.service && systemctl enable docker.service
systemctl start docker


rm -rf docker*
echo -e "Done!"



# Install kubeadm
echo -e "\n\n***************\nInstall kubeadm\n***************\n\n"
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-s390x
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
    https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
set +e
setenforce 0
set -e
yum install -y kubernetes-cni-0.5.1-0.s390x kubectl-${K8S_VERSIONN}-0.s390x  kubelet-${K8S_VERSIONN}-0.s390x   kubeadm-${K8S_VERSIONN}-0.s390x   
systemctl enable kubelet && systemctl start kubelet
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
sed -i "s/--cgroup-driver=systemd/--cgroup-driver=cgroupfs/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
cat << EOF > /var/lib/kubelet/kubeadm-flags.env
KUBELET_EXTRA_ARGS="--cgroup-driver=cgroupfs --runtime-cgroups=/systemd/system.slice --kubelet-cgroups=/systemd/system.slice"
EOF

systemctl daemon-reload
echo -e "\nDone!"

# Install k8s cluster by kubeadm
echo -e "\n\n******************************\nInstall k8s cluster by kubeadm\n******************************\n\n"
mkdir $HOME/k8s-${K8S_VERSION}
kubeadm reset
systemctl start kubelet
kubeadm init --kubernetes-version ${K8S_VERSION} --pod-network-cidr=10.244.0.0/16
mkdir -p ~/.kube
cp /etc/kubernetes/admin.conf ~/.kube/config
kubectl taint nodes --all node-role.kubernetes.io/master-
echo -e "\nDone!"

# Install flannel
echo -e "\n\n***************\nInstall flannel\n***************\n\n"
wget -P $HOME/k8s-${K8S_VERSION}/ https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml
sed -i "s/amd64/s390x/g" $HOME/k8s-${K8S_VERSION}/kube-flannel.yml
kubectl apply -f $HOME/k8s-${K8S_VERSION}/kube-flannel.yml
echo -e "\nDone!"

# Install Kubernetes dashboard
echo -e "\n\n*****************\nInstall dashboard\n*****************\n\n"
#wget -P $HOME/k8s-${K8S_VERSION}/ https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
wget -P $HOME/k8s-${K8S_VERSION}/ https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml
sed -i "s/amd64/s390x/g" $HOME/k8s-${K8S_VERSION}/kubernetes-dashboard.yaml
sed -i "/targetPort: 8443/a\\      nodePort: 32223\n  type: NodePort" $HOME/k8s-${K8S_VERSION}/kubernetes-dashboard.yaml
sed -i "/--auto-generate-certificates/a\\          - --authentication-mode=basic" $HOME/k8s-${K8S_VERSION}/kubernetes-dashboard.yaml
kubectl apply -f $HOME/k8s-${K8S_VERSION}/kubernetes-dashboard.yaml
echo -e "Done!"

# Create user/password authentication & authorization for k8s
echo -e "\n\nCreate user/password\n********************\n"
#echo "admin,admin,admin" >/etc/kubernetes/pki/basic_auth.csv
echo "wukaixing1990,admin,admin" >/etc/kubernetes/pki/basic_auth.csv
sed -i "/etcd-servers/a\\    - --basic-auth-file=\/etc\/kubernetes\/pki\/basic_auth.csv" /etc/kubernetes/manifests/kube-apiserver.yaml
systemctl restart kubelet
echo -e "Done!"

# Waiting for apiserver reload basic-auth config
echo -e "\n\nWaiting for apiserver running"
APISERVERSTATUS=$(ps -ef| grep apiserver| grep basic-auth-file| wc -l)
until [ "${APISERVERSTATUS}" == "1" ]; do
  sleep 10
  printf "*"
  APISERVERSTATUS=$(ps -ef| grep apiserver| grep basic-auth-file| wc -l)
done
echo -e "\n\nDone!"

echo -e "\n\nWaiting for pods running"
PODSSTATUS=$(kubectl get pods -n kube-system 2>/dev/null| grep Running| wc -l)
until [ "${PODSSTATUS}" == "8" ]; do
  sleep 10
  printf "*"
  PODSSTATUS=$(kubectl get pods -n kube-system 2>/dev/null| grep Running| wc -l)
done
echo -e "\n"
cat <<EOF >  $HOME/k8s-${K8S_VERSION}/custom-rbac-role.yaml
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: custom-cluster-role
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: User
  name: admin
  namespace: kube-system
EOF
kubectl create -f $HOME/k8s-${K8S_VERSION}/custom-rbac-role.yaml

# Fix firewall drop rule
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

echo -e "\n\n*****************************************"
echo -e "Kubernetes ${K8S_VERSION} installed successfully!"
echo -e "*****************************************\n\n"