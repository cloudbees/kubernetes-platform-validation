# Installing CJE With Rancher In Digital Ocean

The goal of this document is to describe how to install a Kubernets cluster in **DigitalOcean** using **Rancher**. Unlike AWS, GCE, and Azure, DigitalOcean does not offer many services and it's used mostly for spinning up VMs. As such, running a cluster in DigitalOcean is very close to what we'd experience when running a cluster **on-prem**, be it **bare metal or VMs** created with, for example, VMWare.

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

## Creating A Rancher Server

The first step towards having a Kubernetes cluster is to have a node on which we'll install Rancher server.

Please follow the instructions in the [Creating A Rancher Droplet](droplet.md) document. Once finished, please return to this document.

We can proceed and install Rancher server. Once it's up and running, we'll be able to use it to spin a Kubernetes cluster.

Now we can enter into the droplet.

```bash
ssh -i cje root@$RANCHER_IP
```

Rancher runs as a container. So, our first step towards setting it up is to install Docker.

Please execute only the commands that match your operating system.

If you chose **Ubuntu**, the commands are as follows.

```bash
apt update

apt install -y docker.io
```

If, on the other hand, your operating system is **CentOS**, the commands are as follows.

```bash
yum install -y \
    yum-utils \
    device-mapper-persistent-data \
    lvm2

yum-config-manager --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

yum install -y docker-ce

systemctl start docker
```

No matter the operating system of choice, we'll validate that Docker was installed correctly by outputting its version.

```bash
docker version
```

The output is as follows.

```
Client:
 Version:      18.03.1-ce
 API version:  1.37
 Go version:   go1.9.5
 Git commit:   9ee9f40
 Built:        Thu Apr 26 07:20:16 2018
 OS/Arch:      linux/amd64
 Experimental: false
 Orchestrator: swarm

Server:
 Engine:
  Version:      18.03.1-ce
  API version:  1.37 (minimum version 1.12)
  Go version:   go1.9.5
  Git commit:   9ee9f40
  Built:        Thu Apr 26 07:23:58 2018
  OS/Arch:      linux/amd64
  Experimental: false
```

Now we are ready to set up Rancher.

```bash
docker run -d \
    --restart=unless-stopped \
    -p 80:80 -p 443:443 \
    rancher/rancher:stable
```

We used `-d` to run the container in background (detached). We specified `restart` strategy to `unless-stopped` which will guarantee that Docker will make sure that the container is running even if the process inside it fails. Please note that this strategy does not make your Rancher fault tolerant. If the node hosting our Rancher server goes down, we'd loose everything. However, for the purpose of this exercise, a single Rancher container should be enough.

We published ports `80` and `443`, even though we do not have SL certificates.

Finally, we're using `preview` tag since, at the time of this writing, Rancher 2 is still not production ready. Yet, version two brings a complete overhaul and it would be pointless to invest time in setting up Rancher 1.x.

Let's exit the node and test whether Rancher indeed works.

```bash
exit
```

We'll use [nip.io](http://nip.io) to generate valid domain for Rancher, as well as for the CJE later on. The service provides a wildcard DNS for any IP address. It extracts IP from the nip.io subdomain and sends it back in the response. For example, if we generate 192.168.99.100.nip.io, it'll be resolved to 192.168.99.100. We can even add sub-sub domains like something.192.168.99.100.nip.io, and it would still be resolved to 192.168.99.100. It's a simple and awesome service that quickly became an indispensable part of my toolbox.

```bash
RANCHER_ADDR=$RANCHER_IP.nip.io

echo $RANCHER_ADDR
```

The output of the latter command should be similar to the one that follows.

```
208.68.39.72.nip.io
```

Now we can finally open Rancher UI in browser.

```bash
open "https://$RANCHER_ADDR"
```

> If you are a **Windows* user, Git Bash might not be able to use the `open` command. If that's the case, replace the `open` command with `echo`. As a result, you'll get the full address that should be opened directly in your browser of choice.

If you were quick, you might have seen the message stating that *this site can’t be reached*. If that's the case, it means that Rancher process is still not up-and-running. Please wait a few moments and refresh the screen.

Since we do not have the certificates, you will probably see a warning or an error. If using Chrome, you'll have to click the *ADVANCED* link, followed with *Proceed to [YOUR_IP].nip.io (unsafe)*. If you prefer a different browser, the process should be similar and I'm sure you'll know how to proceed.

You should see Rancher's welcome screen asking you to create the initial administrative password. Feel free to choose any. Once finished, please click the *Continue* button.

![Figure 1: Rancher's welcome screen](img/rancher-welcome.png)

Next, you will be asked to specify *Rancher Server URL*. It is already pre-populated with the `nip.io` domain we used and all you have to do is click the *Save URL* button.

![Figure 2: Rancher's Server URL screen](img/rancher-server-url.png)

Before we proceed and create a cluster using Rancher, we'll need to set up storage for state generated by our applications.

## Setting Up External Storage

> Feel free to skip this whole section if you do not plan to use NFS.

For simplicity, we'll set up an NFS server on the same node where Rancher is running. Please don't do that for in "real-world" situations. Rather, you should have one or more separate NFS servers dedicated to a Kubernetes cluster.

The instructions that follow will require the IP of the NFS server. Please us Rancher IP with the command that follows.

```bash
NFS_SERVER_ADDR=$RANCHER_IP
```

Please follow the instructions in the [Creating An NFS Server](../storage/nfs/server.md) document. Once finished, please return to this document.

## Creating A Kubernetes Cluster

When using Rancher, the only option for creating a Kubernetes cluster is through its UI. So, we'll start by opening Rancher's home screen.

```bash
open "https://$RANCHER_ADDR"
```

Please click the *Add Cluster* button, and select *DigitalOcean*. Type *cje* as the *Cluster Name*.

Next, we will define the nodes that will constitute our cluster. Please scroll down to the *Node Pool* section.

First we'll create master nodes. We'll need three if we are to create a fault tolerant cluster. Master nodes need to have quorum before committing any decision. If we'd have two master nodes, and one of them fails, we'd loose quorum since over 50% is required.

Type *master* as the *Name Prefix*, set *Count* to *3*, and select *etcd* and *Control* check boxes.

The only thing left, when defining master nodes, is to decide which node specifications we'll use. We do that through Node Templates.

Please click the *Add Node Template* button (icon with the **+** sign). You'll have to type or, more likely, paste the DigitalOcean token we created earlier. Once inside the template screen, please select *New York 3* as the *Region*, select *2 GB RAM, 60 GB Disk, 2 vCPUs* as *Droplet Size*, and type *k8s* as the *Name*. The purpose of each of those fields should be self-explanatory.

The only thing left to do, before we create the new template, is to choose the image. If you prefer **Ubuntu**, please select **Ubuntu 16.04 x64**. Similarly, **CentOS** users should pick **CentOS 7.X x64**.

Once finished, click the *Create* button.

Next, we'll repeat a similar process to define worker nodes. Those are the nodes where our applications will run.

Please click the *Add Node Pool* button. A new row will be added. Type *worker* as the *Name Prefix*, set *Count* to *3*, and make sure that the  *Worker* checkbox is selected.

We are almost done. All that's left is to click the *Create* button, and be patient.

![Figure 3: Rancher's Add Cluster screen](img/rancher-create-cluster.png)

After instructing Rancher to create a new cluster, we're redirected to the *Clusters* screen. At the moment, *cje* should be the only cluster managed by Rancher and its state should be *Provisioning*. Please click the *cje* link in the *Cluster Name* column.

![Figure 4: Rancher's Clusters screen](img/rancher-clusters.png)

Now we need to be patient and wait until everything is green. It should take around 10 minutes.

![Figure 5: Rancher's Cluster Dashboard screen](img/rancher-cluster-dashboard.png)

Once our new cluster is fully operational, we can configure out local `kubectl`. We'll create a separate config file only for this cluster.

```bash
vim do-kube-config.yaml
```

Feel free to change `vim` to your favorite editor. All we'll need is to paste some content, so any editor you're comfortable with should do.

Please go back to Rancher UI, click the *Kubeconfig File* button, followed with a click to the *Copy to Clipboard* link.

![Figure 6: Rancher's Kubeconfig screen](img/rancher-kubeconfig.png)

Next, we need to go back to the terminal window where we have `do-kube-config.yaml` opened in our favorite editor, paste the content we just copied, and save the file. If you're using `vim`, you should press `i` to enter into the insert mode, paste the copied content, press *esc* button to exit the insert mode, press colon (`:`) to enter into the command mode, and type `wq` to save and quit. If you prefer something other than `vim`, I'm sure you'll know how to do the same operations (paster, save, and exit).

Kubectl uses environment variable `KUBECONFIG` to know the location of the config file, so we'll need to export it with the path to the file we just created.

```bash
export KUBECONFIG=$PWD/do-kube-config.yaml
```

For now, we'll do only a rudimentary validation of the cluster by retrieving the nodes. If everything worked as expected, we should have six of them, three dedicated to master nodes (`controlplane` and `etcd`), and the other three as workers.

```bash
kubectl get nodes
```

The output is as follows.

```
NAME    STATUS ROLES             AGE  VERSION
master1 Ready  controlplane,etcd 1h   v1.10.1
master2 Ready  controlplane,etcd 1h   v1.10.1
master3 Ready  controlplane,etcd 1h   v1.10.1
worker1 Ready  worker            1h   v1.10.1
worker2 Ready  worker            1h   v1.10.1
worker3 Ready  worker            1h   v1.10.1
```

We're almost finished with creating the cluster. All that's left is to create two namespaces. We'll use `cjoc` to host CloudBees Operations Center as well as for the managed masters we'll spin up later. The second namespace will be called `build`. That where our builds will run Pods. With such separation, we'll try to mitigate some of the risks builds might introduce to CJOC and masters.

```bash
kubectl create ns cjoc

kubectl create ns build
```

## Validating RBAC

Please follow the instructions from the [Validating RBAC](../security/rbac-validate.md) document. Return here when finished.

## Creating A Load Balancer

We'll need to create an external load balancer (LB). It's purpose will be to guarantee a stable entry point to the cluster. Such an LB should forward requests to one of the worker nodes. There's no need to have any special criteria which worker node that is, as long as it's healthy. In other words, the external LB will guarantee that requests enter the cluster even if some of the nodes are down.

Please follow the instructions in the [Creating A DigitalOcean Load Balancer](lb.md) document.

## Validating Load Balancer And Ingress

Please follow the instructions from the [Validating Load Balancer And Ingress](../network/ingress-validate.md) document. Return here when finished.

## Creating StorageClasses

### NFS

To create an NFS StorageClass, please follow the instructions in the [Creating StorageClass with NFS Client Provisioner](../storage/nfs/nfs-client-provisioner.md) document. Return here when finished.

If applicable and desired, please follow the instructions from [Making A StorageClass Default](../storage/storage-default.md) document. Return here when finished.

## Validating StorageClasses

Follow the instructions from the [Validating StorageClasses](../storage/storage-validate.md) document. Return here when finished.

## Installing CJE

```bash
open "https://downloads.cloudbees.com/cje2/latest/"

# Copy the link address of cje2 Kubernetes release

RELEASE_URL=[...]

curl -o cje.tgz $RELEASE_URL

tar -xvf cje.tgz
```

```
x cje2_2.121.1.2_kubernetes/
x cje2_2.121.1.2_kubernetes/cjoc-external-masters.yml
x cje2_2.121.1.2_kubernetes/INSTALLATION.md
x cje2_2.121.1.2_kubernetes/SCALING.md
x cje2_2.121.1.2_kubernetes/TROUBLESHOOTING.md
x cje2_2.121.1.2_kubernetes/PROXY.md
x cje2_2.121.1.2_kubernetes/ANALYTICS.md
x cje2_2.121.1.2_kubernetes/cje.yml
```

```bash
cd cje2_*

ls -l
```

```
-rw-r--r--  1 vfarcic  staff    158  6 Jun 07:06 ANALYTICS.md
-rw-r--r--  1 vfarcic  staff   5144  6 Jun 07:06 INSTALLATION.md
-rw-r--r--  1 vfarcic  staff   1498  6 Jun 07:06 PROXY.md
-rw-r--r--  1 vfarcic  staff   1466  6 Jun 07:06 SCALING.md
-rw-r--r--  1 vfarcic  staff   4950  6 Jun 07:06 TROUBLESHOOTING.md
-rw-r--r--  1 vfarcic  staff  11884  6 Jun 07:06 cje.yml
-rw-r--r--  1 vfarcic  staff    509  6 Jun 07:06 cjoc-external-masters.yml
```

```bash
cat cje.yml

kubectl create ns jenkins

cat cje.yml \
    | sed -e \
    "s@https://cje.example.com@http://cje.example.com@g" \
    | sed -e \
    "s@cje.example.com@$LB_ADDR@g" \
    | sed -e \
    "s@ssl-redirect: \"true\"@ssl-redirect: \"false\"@g" \
    | sed -e \
    "s@# storageClassName: some-storage-class@storageClassName: cje-storage@g" \
    | kubectl --namespace cjoc \
    apply -f -
```

```
serviceaccount "cjoc" created
role "master-management" created
rolebinding "cjoc" created
configmap "cjoc-config" created
configmap "cjoc-configure-jenkins-groovy" created
statefulset "cjoc" created
service "cjoc" created
ingress "cjoc" created
serviceaccount "jenkins" created
role "pods-all" created
rolebinding "jenkins" created
configmap "jenkins-agent" created
```

```bash
kubectl -n cjoc \
    rollout status sts cjoc
```

```
Waiting for 1 pods to be ready...
statefulset rolling update complete 1 pods at revision cjoc-578b8fd6b4...
```

```bash
kubectl -n cjoc get all
```

```
NAME                            DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deploy/nfs-client-provisioner   1         1         1            1           51m

NAME                                   DESIRED   CURRENT   READY     AGE
rs/nfs-client-provisioner-69688c76dd   1         1         1         51m

NAME                DESIRED   CURRENT   AGE
statefulsets/cjoc   1         1         1m

NAME                                         READY     STATUS    RESTARTS   AGE
po/cjoc-0                                    1/1       Running   0          1m
po/nfs-client-provisioner-69688c76dd-b2bjj   1/1       Running   0          51m

NAME       TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)            AGE
svc/cjoc   ClusterIP   10.43.128.241   <none>        80/TCP,50000/TCP   1m
```

```bash
open "http://$LB_ADDR/cjoc"

kubectl -n cjoc exec cjoc-0 -- \
    cat /var/jenkins_home/secrets/initialAdminPassword
```

```
c9b802a409a04d1f8755e9d394749a58
```

```bash
# Copy the output and paste it into Jenkins UI field *Administrative password*

# Click the *Continue* button

# Click the *Use a license key* button

# Type your *License Key* and *License Certificate*

# Click the *OK* button

# Click the *Install suggested plugins* button

# Fill in the field in the *Create First Admin User* screen

# Click the *Save and Continue* button

# Click the *Start using Operations Center* button

kubectl -n cjoc get pvc
```

```
NAME                  STATUS    VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
jenkins-home-cjoc-0   Bound     pvc-271f09c1-69f1-11e8-b65a-ea9238c4f6a5   20Gi       RWO            cje-storage    11m
```

```bash
kubectl get pv
```

```
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS    CLAIM                      STORAGECLASS   REASON    AGE
pvc-271f09c1-69f1-11e8-b65a-ea9238c4f6a5   20Gi       RWO            Delete           Bound     cjoc/jenkins-home-cjoc-0   cje-storage              15m
```

### Creating Managed Masters

TODO: Create

TODO: Fail and confirm that the state is preserved

### Managed Agents (PodTemplates)

TODO

### External Masters

TODO

### External Agents

TODO

## Validating CJE

## Destroying The Cluster

TODO
