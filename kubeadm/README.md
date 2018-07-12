# Installing CJE With Rancher In Digital Ocean

The goal of this document is to describe how to install a Kubernets cluster in **DigitalOcean** using **kubeadm**. Unlike AWS, GCE, and Azure, DigitalOcean does not offer many services and it's used mostly for spinning up VMs. As such, running a cluster in DigitalOcean is very close to what we'd experience when running a cluster **on-prem**, be it **bare metal or VMs** created with, for example, VMWare.

You will be able to choose between **Ubuntu** and **CentOS** as operating systems. For storage, the instructions explain setup of a Kubernetes **NFS** client. We'll use Digital Ocean's load balancer. The logic behind its setup should be applicable to any other load balancer.

Throughout the document, we'll have sets of validations aimed at confirming that the cluster is set up correctly and can be used to install **CJE**. Feel free to jump straight into validations if you already have an operational cluster. The validations are focused on **RBAC** and **ServiceAccounts**, **load balancers** and **Ingress**, and **storage**.

Once we're confident that the cluster works as expected, we'll proceed with the CJE installation. We'll create CJOC, a managed master, and a job that will run in a separate Namespace.

We'll try to do as much work as possible through CLI. In a few cases, it will not be possible (or practical) to accomplish some tasks through a terminal window, so we'll have to jump into UIs. Hopefully, that will be only for very brief periods. The reason for insisting on CLI over UI, lies in the fact that commands are easier to reproduce and lead us towards automation. More importantly, I have a medical condition that results in severe pain when surrounded with many colors. The only medically allowed ones are black, white, and green. Unfortunatelly, most UIs are not designed for people with disabilities like mine.

At some later date, this document will be extended with the following items. Feel free to suggest additional ones.

* HAProxy as external LB
* nginx as external LB
* Ceph storage
* Gluster storage
* Basic CNI networking
* Flannel networking
* Calico networking
* Weave networking

## Requirements

We'll need a few prerequisites first.

Please make sure that you have the following items.

* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/): Used for communication with a Kubernetes cluster.
* [jq](https://stedolan.github.io/jq/): Used for formatting and filtering of JSON outputs.
* ssh-keygen: Used for generating SSH keys required for accessing nodes.
* GitBash (if Windows): Used for compatibility with other operating systems. Please use it **only if you are a Windows user**. It is available through [Git](https://git-scm.com/) setup.
* [DigitalOcean account](https://www.digitalocean.com): That's where we'll create a cluster.
* [doctl](https://github.com/digitalocean/doctl): CLI used for interaction with DigitalOcean API.

## Setting Up External Storage

We'll need a node on which we'll install NFS server that will serve as the solution for external storage. Feel free to create the node in any way and place you like. If you choose to host it in DigitalOcean, you might want to follow the instructions from the [Creating A Rancher Droplet](../rancher-do/droplet.md) document. Once finished, please return to this document.

For simplicity, we'll set up an NFS server on the same node where Rancher is running. Please don't do that for in "real-world" situations. Rather, you should have one or more separate NFS servers dedicated to a Kubernetes cluster.

The instructions that follow will require the IP of the NFS server.

```bash
NFS_SERVER_ADDR=[...]
```

Replace `[...]` with the IP of the node where you're planning to install NFS server. If you followed the instructions from the [Creating A Rancher Droplet](../rancher-do/droplet.md) document, the IP is already stored in the environment variable `RANCHER_IP` and you can replace the previous command with `NFS_SERVER_ADDR=$RANCHER_IP`.

Please follow the instructions in the [Creating An NFS Server](../storage/nfs/server.md) document. Once finished, please return to this document.

## Creating A Cluster With kubeadm

**The commands that follow apply only to Ubuntu nodes. CentOS/RHEL is coming up soon.**

```bash
export DIGITALOCEAN_API_TOKEN=[...]

cd kubeadm

cat ubuntu-image.json
```

```json
{
  "variables": {
    "do_region": "nyc3",
    "snapshot_name": "snapshot-kubernetes"
  },
  "builders": [{
    "type": "digitalocean",
    "image": "ubuntu-16-04-x64",
    "region": "{{ user `do_region` }}",
    "size": "512mb",
	"ssh_username": "root",
	"snapshot_name": "{{ user `snapshot_name` }}-{{ isotime \"2006-01-02\" }}"
  }],
  "provisioners": [{
    "type": "shell",
    "inline": [
      "sudo apt-get clean",
      "sudo apt-get update",
      "sudo apt-get install -y apt-transport-https ca-certificates",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      "sudo add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce=17.06.2~ce-0~ubuntu",
      "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - ",
      "sudo add-apt-repository \"deb http://apt.kubernetes.io/ kubernetes-xenial main\"",
      "sudo apt-get update ",
      "sudo apt-get install -y kubectl=1.9.7-00 kubeadm=1.9.7-00 kubelet=1.9.7-00 python-pip",
      "pip install s3cmd"
    ]
  }]
}
```

```bash
packer build -machine-readable \
    ubuntu-image.json \
    | tee image.log

ssh-keygen -t rsa -P "" -f k8s-key

export TF_VAR_token=$DIGITALOCEAN_API_TOKEN

export TF_VAR_k8s_snapshot_id=$(grep \
    'artifact,0,id' \
    image.log \
    | cut -d: -f2)

terraform init

terraform plan -out plan
```

```
...
Plan: 2 to add, 0 to change, 0 to destroy.

------------------------------------------------------------------------

This plan was saved to: plan

To perform exactly these actions, run the following command to apply:
    terraform apply "plan"
```

```bash
terraform apply plan
```

```
...
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

master-1-ip = 45.55.52.229
worker-ip = [
    159.203.81.189,
    138.197.1.1
]
```

```bash
ssh -i k8s-key \
    root@$(terraform output master-1-ip)

sysctl net.bridge.bridge-nf-call-iptables=1

kubeadm init \
    --pod-network-cidr="10.244.0.0/16" \
    | sudo tee /opt/kube-init.log

export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl get nodes
```

```
NAME           STATUS     ROLES     AGE       VERSION
k8s-master-1   NotReady   master    39s       v1.9.7
```

```bash
kubectl apply \
    -f https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml
```

```
clusterrole "flannel" created
clusterrolebinding "flannel" created
serviceaccount "flannel" created
configmap "kube-flannel-cfg" created
daemonset "kube-flannel-ds" created
```

```bash
kubectl get nodes
```

```
NAME           STATUS    ROLES     AGE       VERSION
k8s-master-1   Ready     master    1m        v1.9.7
```

```bash
kubeadm token create \
    --print-join-command > k8s_join_cmd

cat k8s_join_cmd
```

```
kubeadm join --token fc23c6.93b1721b2d48af0f 159.203.115.175:6443 --discovery-token-ca-cert-hash sha256:b03010c2298f423d8aea001d791943ff2143839030a6dfc5b4bb1214fd10bab0
```

```bash
exit

scp -i k8s-key \
    root@$(terraform output master-1-ip):/etc/kubernetes/admin.conf \
    kubeconf

export KUBECONFIG=kubeconf

kubectl get nodes

scp -i k8s-key \
    root@$(terraform output master-1-ip):/root/k8s_join_cmd \
    k8s_join_cmd

NODE_1_IP=$(terraform output worker-ip \
    | head -n 1 \
    | sed 's/.$//')

scp -i k8s-key k8s_join_cmd \
    root@$NODE_1_IP:/root/k8s_join_cmd

NODE_2_IP=$(terraform output worker-ip \
    | tail -n 1)

scp -i k8s-key k8s_join_cmd \
    root@$NODE_2_IP:/root/k8s_join_cmd

ssh -i k8s-key root@$NODE_1_IP \
    "sysctl net.bridge.bridge-nf-call-iptables=1"

ssh -i k8s-key root@$NODE_1_IP \
    "chmod +x k8s_join_cmd && /root/k8s_join_cmd"

ssh -i k8s-key root@$NODE_2_IP \
    "sysctl net.bridge.bridge-nf-call-iptables=1"

ssh -i k8s-key root@$NODE_2_IP \
    "chmod +x k8s_join_cmd && /root/k8s_join_cmd"

kubectl get nodes
```

```
NAME         STATUS    ROLES     AGE       VERSION
k8s-master-1 Ready     master    14m       v1.9.7
worker-1     Ready     <none>    2m        v1.9.7
worker-2     Ready     <none>    21s       v1.9.7
```

```bash
kubectl create ns cjoc
```

```
namespace "cjoc" created
```

```bash
kubectl create ns build
```

```
namespace "build" created
```

```bash
kubectl get ns
```

```
NAME          STATUS    AGE
build         Active    8s
cjoc          Active    8s
default       Active    10m
kube-public   Active    10m
kube-system   Active    10m
```

## Validating RBAC

Please follow the instructions from the [Validating RBAC](../security/rbac-validate.md) document. Return here when finished.