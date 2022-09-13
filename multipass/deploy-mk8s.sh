#!/bin/bash

set -e
set -x

get_help(){
    echo -e "\nUsage: deploy-mk8s.sh <K8s version> <Antrea Version>\n"
    echo -e "\nExample ./deploy-mk8s.sh 1.23.0 v1.8.0"
}

if [ $# -eq 0 ]; then
    get_help
    exit 1
fi

declare -a cluster=("control-plane" "workera" "workerb")
export K8S_VERSION=$1
export TAG=$2

launch_multipass_nodes(){
    for i in "${cluster[@]}"
    do
        echo "Launching $i"
        multipass launch --name "$i" --cpus 2 -m 2G
    done
}

setup_multipass_nodes(){

for i in "${cluster[@]}"
do
   echo "Setting up host $i"
   multipass exec "$i" -- /bin/bash -c "cat <<EOF > setup_hosts.sh
   cat <<ABC | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
ABC

cat <<DEF | sudo tee -a /etc/sysctl.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
DEF

sudo modprobe br_netfilter
sudo sysctl -p

# Apply sysctl params without reboot
sudo sysctl --system

# (Install containerd)
sudo apt-get update && sudo apt-get install -y containerd

# Configure containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

# Restart containerd
sudo systemctl restart containerd

# Install kubelet, kubectl and kubeadm
sudo apt-get update && sudo apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<XYZ | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
XYZ
sudo apt-get update
sudo apt-get install -y kubelet=${K8S_VERSION}-00 kubeadm=${K8S_VERSION}-00 kubectl=${K8S_VERSION}-00
sudo apt-mark hold kubelet kubeadm kubectl
EOF"
    multipass exec "$i" -- chmod +x setup_hosts.sh
    multipass exec "$i" -- /home/ubuntu/setup_hosts.sh
done
}

initializa_control_plane(){
    echo "## Setting up control plane ##"
    multipass exec control-plane -- /bin/bash -c "sudo kubeadm init --pod-network-cidr=10.200.0.0/16"
    multipass exec control-plane -- /bin/bash -c "mkdir -p $HOME/.kube"
    multipass exec control-plane -- /bin/bash -c "sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config"
    multipass exec control-plane -- /bin/bash -c "sudo chown $(id -u):$(id -g) $HOME/.kube/config"
}

add_worker_node(){
    join_command=$(multipass exec control-plane -- /bin/bash -c "sudo kubeadm token create --print-join-command")
    join_command=$(echo $join_command | cut -d' ' -f 2-)

    for i in "${cluster[@]}"
    do
        if [ ! "$i" == "control-plane" ]; then
            multipass exec "$i" -- /bin/bash -c "sudo kubeadm $join_command"
        fi
    done
}

get_kubeconfig(){
    multipass transfer control-plane:/home/ubuntu/.kube/config - > multipass-kubeconfig
}

install_antrea(){
    kubectl --kubeconfig multipass-kubeconfig apply -f https://github.com/antrea-io/antrea/releases/download/$TAG/antrea.yml
    echo "Antrea installation in progress"
    echo "Run kubectl get pods -A --kubeconfig multipass-kubeconfig to verify antrea status"
}

cleanup(){
    for i in "${cluster[@]}"
    do
        echo "Cleaning up cluster"
        multipass delete "$i"
        multipass purge
    done
}

launch_multipass_nodes
setup_multipass_nodes
initializa_control_plane
add_worker_node
get_kubeconfig
install_antrea
