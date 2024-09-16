# k8s-distributed-inference

## Kubernetes Setup

## DRA Setup

```bash
git clone https://github.com/NVIDIA/k8s-dra-driver.git
cd k8s-dra-driver
./demo/clusters/kind/create-cluster.sh
./demo/clusters/kind/build-dra-driver.sh
./demo/clusters/kind/install-dra-driver.sh
```

Verify the NVidia DRA driver is functioning

> kubectl get pods -n nvidia-dra-driver

```bash
NAMESPACE           NAME                                       READY   STATUS    RESTARTS   AGE
nvidia-dra-driver   nvidia-dra-plugin-lt7qh                    1/1     Running   0          32s
```

## MIG Setup
Before running the MIG configuration script, check the current status of your GPU on the host.
> nvidia-smi

Check GPUs visible on the worker node
> docker exec k8s-dra-driver-cluster-worker nvidia-smi

They output should be the same. If not, be sure to run this against the worker node:
```bash
# Unmount the masked /proc/driver/nvidia to allow
# dynamically generated MIG devices to be discovered
docker exec -it k8s-dra-driver-cluster-worker umount -R /proc/driver/nvidia
```
We are using 1 NVIDIA A100 80GB. This mig config partitions it into 7 1g.10gb MIG devices.

Apply the half-balanced mig config
```bash
git clone this repo
sudo -E nvidia-mig-parted apply -f mig-config.yaml -c half-balanced
```
Check status of the GPU
> docker exec -it k8s-dra-driver-cluster-worker nvidia-smi -L

Output should look something like this:
```console

GPU 0: NVIDIA A100 80GB PCIe (UUID: GPU-295b72d2-e23d-baa4-1b87-88bc3b68fd08)
  MIG 1g.10gb     Device  0: (UUID: MIG-c1d3d074-7dc1-5e89-8a5f-6d0b08327092)
  MIG 1g.10gb     Device  1: (UUID: MIG-84e0b369-ad9b-5b6f-a11f-74e7d7de0637)
  MIG 1g.10gb     Device  2: (UUID: MIG-a0f16850-6590-5284-af50-75045a9924bf)
  MIG 1g.10gb     Device  3: (UUID: MIG-201001c5-e1cd-5e83-93b5-067098c41158)
  MIG 1g.10gb     Device  4: (UUID: MIG-a4b98058-b6dc-579e-8b08-7c4d67791eb6)
  MIG 1g.10gb     Device  5: (UUID: MIG-20bf0814-715e-558a-a6fd-6d01e258fe51)
  MIG 1g.10gb     Device  6: (UUID: MIG-d7b09a5a-7aa7-5d3d-afb7-2f818bc1635b)
```

## Check DRA Resource slices
After the MIG configuration is applied, we may need to restart the DRA driver kubelet plugin pod to trigger the changes.

> kubectl get resourceslice -o yaml

Output should include 7 devices that look something like this:

```yaml
apiVersion: v1
items:
- apiVersion: resource.k8s.io/v1alpha3
  kind: ResourceSlice
  metadata:
    generateName: k8s-dra-driver-cluster-worker-gpu.nvidia.com-
    generation: 1
    name: k8s-dra-driver-cluster-worker-gpu.nvidia.com-76gj4
    ownerReferences:
    - apiVersion: v1
      controller: true
      kind: Node
      name: k8s-dra-driver-cluster-worker
    uid: 05883b3a-005d-4ef0-9f18-f9c04c35f6a7
  spec:
    devices:
    - basic:
        attributes:
          architecture:
            string: Ampere
          brand:
            string: Nvidia
          cudaComputeCapability:
            version: 8.0.0
          cudaDriverVersion:
            version: 12.6.0
          driverVersion:
            version: 560.35.3
          index:
            int: 6
          parentIndex:
            int: 0
          parentUUID:
            string: GPU-08ca734a-eacd-b37e-189a-ba50997e441d
          productName:
            string: NVIDIA A100 80GB PCIe
          profile:
            string: 1g.10gb
          type:
            string: mig
          uuid:
            string: MIG-a280f2d0-03b7-5a7c-adea-94cb1d0726ba
        capacity:
          copyEngines: "1"
          decoders: "0"
          encoders: "0"
          jpegEngines: "0"
          memory: 9728Mi
          memorySlice6: "1"
          multiprocessors: "14"
          ofaEngines: "0"
      name: gpu-0-mig-19-6-1
...
```

## Command to deploy WebAPI Server on GPU

```bash
kubectl patch deployment localai-main \
    --type='json' \
    -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args/2", "value": "--p2ptoken=<new-token>"}, {"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "localai/localai:latest-aio-gpu-nvidia-cuda-12"}]'
```

## Command to deploy Workers with GPU 

```bash
kubectl patch deployment localai-workers \
    --type='json' \
    -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args/2", "value": "--p2ptoken=<new-token>"}, {"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "localai/localai:latest-aio-gpu-nvidia-cuda-12"}]'
```