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
