# Running LocalAI on Azure

## Provision Node on Azure

Copy the environment sample file and update it:

```bash
cp .env-sample .env
```

Once updated, source it to your environment:

```bash
source .env
```

Create a resource group if you have not created this already:

```bash
az group create \
    --name "${AZURE_RESOURCE_GROUP}" \
    --location "${AZURE_REGION}"
```

Create the VM:

```bash
az vm create \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --size "${VM_SIZE}" \
    --name "${VM_NAME}" \
    --location "${AZURE_REGION}" \
    --admin-username "${USER_NAME}" \
    --ssh-key-values "${SSH_KEY}" \
    --authentication-type ssh \
    --image canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest \
    --public-ip-address-dns-name "${VM_NAME}" \
    --os-disk-size-gb 300 \
    --security-type standard
```

To install the Nvidia GPU drivers enable the extension by running the following command (this command takes a while to finish):

```bash
az vm extension set \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --vm-name "${VM_NAME}" \
    --name NvidiaGpuDriverLinux \
    --publisher Microsoft.HpcCompute \
    --settings '{ \
        "updateOS": "true" \
    }'
```

SSH into the machine:

```bash
ssh -i ${SSH_KEY%.pub} ${USER_NAME}@${VM_NAME}.${AZURE_REGION}.cloudapp.azure.com
```

You can see the extension installation process inside the VM by running the following command from the VM:

```bash
tail -f /var/log/azure/nvidia-vmext-status
```

A successful generally looks like this:

```console
$ tail -f /var/log/azure/nvidia-vmext-status
...
...
+-----------------------------------------------------------------------------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI        PID   Type   Process name                              GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|  No running processes found                                                             |
+-----------------------------------------------------------------------------------------+
Already installed. Not doing anything here.
Writing status: /var/lib/waagent/Microsoft.HpcCompute.NvidiaGpuDriverLinux-1.12.0.0/status/0.status
```

This Az CLI command also gives you status of the extension's installation:

```bash
az vm extension list \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --vm-name "${VM_NAME}" \
    -o table
```

## Setup Host with necessary tools

> [!NOTE]
> All these instructions are run inside the VM we provisioned earlier.

Clone this repository

```bash
git clone https://github.com/sozercan/k8s-distributed-inference
cd k8s-distributed-inference
```

Run the following script to install all the necessary tools:

```bash
./scripts/node-setup.sh
```

> [!TIP]
> To use `docker` without `sudo` run `newgrp docker`

## MIG Setup on Host

In this step we will partition the GPU into multiple instances of GPU. Check the current status of your GPU on the host:

```bash
nvidia-smi
```

Your machine should have one NVIDIA A100 80GB if you have used the machine SKU as `Standard_NC24ads_A100_v4`. Following command partitions the GPU into 7 1g.10gb MIG devices with configuration in [mig-config.yaml](configs/mig-config.yaml).

```bash
# This value is either Standard_NC24ads_A100_v4, Standard_NC48ads_A100_v4 or Standard_NC96ads_A100_v4.
# Adjust this based on your machine type.
export MIG_CONFIG="Standard_NC24ads_A100_v4"
sudo -E nvidia-mig-parted apply -f configs/mig-config.yaml -c $MIG_CONFIG
```

```bash
nvidia-smi -L
```

Output should look something like this:

```bash
GPU 0: NVIDIA A100 80GB PCIe (UUID: GPU-295b72d2-e23d-baa4-1b87-88bc3b68fd08)
  MIG 1g.10gb     Device  0: (UUID: MIG-c1d3d074-7dc1-5e89-8a5f-6d0b08327092)
  MIG 1g.10gb     Device  1: (UUID: MIG-84e0b369-ad9b-5b6f-a11f-74e7d7de0637)
  MIG 1g.10gb     Device  2: (UUID: MIG-a0f16850-6590-5284-af50-75045a9924bf)
  MIG 1g.10gb     Device  3: (UUID: MIG-201001c5-e1cd-5e83-93b5-067098c41158)
  MIG 1g.10gb     Device  4: (UUID: MIG-a4b98058-b6dc-579e-8b08-7c4d67791eb6)
  MIG 1g.10gb     Device  5: (UUID: MIG-20bf0814-715e-558a-a6fd-6d01e258fe51)
  MIG 1g.10gb     Device  6: (UUID: MIG-d7b09a5a-7aa7-5d3d-afb7-2f818bc1635b)
```

## Kubernetes Setup with k8s-dra-driver

We will use the NVIDIA/k8s-dra-driver to set up Kubernetes and then use the k8s-dra-driver to expose MIG to the Kubernetes control-plane:

```bash
mkdir -p artifacts
pushd artifacts
git clone https://github.com/NVIDIA/k8s-dra-driver.git

pushd k8s-dra-driver
git checkout 380045af634a39fc5311c6ad1379174a2c33cfb3

./demo/clusters/kind/create-cluster.sh
./demo/clusters/kind/build-dra-driver.sh
./demo/clusters/kind/install-dra-driver.sh

popd
popd
```

Verify the Nvidia DRA driver is functioning:

```bash
kubectl get pods -n nvidia-dra-driver
```

```bash
NAMESPACE           NAME                         READY   STATUS    RESTARTS   AGE
nvidia-dra-driver   nvidia-dra-plugin-lt7qh      1/1     Running   0          32s
```

Check the current status of your GPU on the host:

```bash
nvidia-smi
```

Check the same GPUs are visible on the worker node as well. The output of the following command and the previous command should match:

```bash
docker exec k8s-dra-driver-cluster-worker nvidia-smi
```

> [!TIP]
> When you restart the node, you may see a mismatch in what's on the host and what's inside the kind worker node. To fix that run the following command:
>
> ```bash
> # Unmount the masked /proc/driver/nvidia to allow
> # dynamically generated MIG devices to be discovered
> docker exec -it k8s-dra-driver-cluster-worker umount -R /proc/driver/nvidia
> ```

Ensure that the Kubernetes control plane has picked up the MIGs we have created (this should match the output of `nvidia-smi`):

```bash
kubectl get resourceslice -o json | jq -r \
    '.items[0].spec.devices[] | .basic as $b | "MIG \($b.attributes.profile.string) Device \($b.attributes.index.int): (UUID: \($b.attributes.uuid.string))"' | \
    sort -k3 -n
```
