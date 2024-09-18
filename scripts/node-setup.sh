#!/usr/bin/env bash

set -euo pipefail
set -x

function install_prereq_packages() {
    sudo apt update || true
    sudo apt install -y \
        jq bat hwinfo ubuntu-drivers-common \
        make apt-transport-https \
        ca-certificates curl gnupg net-tools
}

function install_docker() {
    # Install Docker
    sudo apt-get update || true
    sudo apt-get install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
        sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update || true
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo docker run hello-world
    sudo usermod -aG docker $USER
}

function install_kind() {
    pushd $(mktemp -d)
    [ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    popd
}

function install_kubectl() {
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor | sudo tee /etc/apt/keyrings/kubernetes-apt-keyring.gpg >/dev/null
    sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update || true
    sudo apt-get install -y kubectl
}

function install_helm() {
    if ! command -v helm &>/dev/null; then
        curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg >/dev/null
        sudo apt-get install apt-transport-https --yes
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
        sudo apt-get update || true
        sudo apt-get install -y helm
    else
        echo "Helm is already installed"
    fi
}

function install_gpu_operator() {
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia &&
        helm repo update

    helm install --wait --generate-name \
        -n gpu-operator --create-namespace \
        nvidia/gpu-operator \
        --set mig.strategy=single \
        --set migManager.env[0].name=WITH_REBOOT \
        --set-string migManager.env[0].value=true

    kubectl patch clusterpolicies.nvidia.com/cluster-policy \
        --type='json' \
        -p='[{"op":"replace", "path":"/spec/mig/strategy", "value":"single"}]'

    kubectl label $(kubectl get nodes -l agentpool=mignode -o name) nvidia.com/mig.config=all-1g.10gb --overwrite
}

function install_nvidia_toolkit() {
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor | sudo tee /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg >/dev/null &&
        curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    sudo sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list
    sudo apt-get update || true
    sudo apt-get install -y nvidia-container-toolkit

    sudo nvidia-ctk runtime configure --runtime=docker --set-as-default --cdi.enabled
    sudo nvidia-ctk config --set accept-nvidia-visible-devices-as-volume-mounts=true --in-place
    sudo systemctl restart docker
}

function install_nvidia_mig_manager() {
    pushd $(mktemp -d)
    curl -LO https://github.com/NVIDIA/mig-parted/releases/download/v0.9.1/nvidia-mig-manager_0.9.1-1_amd64.deb
    sudo chown -Rv _apt:root .
    sudo chmod -Rv 700 .
    sudo apt install -y ./nvidia-mig-manager_0.9.1-1_amd64.deb
    popd
}

# Parse command-line arguments
install_gpu_operator_flag=false
install_nvidia_toolkit_flag=false
install_nvidia_mig_manager_flag=false

for arg in "$@"; do
    case $arg in
        --install-gpu-operator)
        install_gpu_operator_flag=true
        shift;;
        --install-nvidia-toolkit)
        install_nvidia_toolkit_flag=true
        shift;;
        --install-nvidia-mig-manager)
        install_nvidia_mig_manager_flag=true
        shift;;
        *)
        echo "Unknown option: $arg"
        exit 1;;
    esac
done

install_prereq_packages
install_docker
install_kind
install_kubectl
install_helm

# Install based on the parsed flags
if [[ "$install_gpu_operator_flag" == true ]]; then
    install_gpu_operator
fi

if [[ "$install_nvidia_toolkit_flag" == true ]]; then
    install_nvidia_toolkit
fi

if [[ "$install_nvidia_mig_manager_flag" == true ]]; then
    install_nvidia_mig_manager
fi