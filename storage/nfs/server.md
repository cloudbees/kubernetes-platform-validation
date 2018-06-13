# Creating An NFS Server

The first order of business is to SSH into the node where we'll install and set up NFS.

```bash
NFS_SERVER_ADDR=[...]

ssh -i cje root@$NFS_SERVER_ADDR
```

Please replace `[...]` with the IP of the node where we'll install NFS server. The second command assumes that node is accessible using SSH key file `cje`.

The steps required to install NFS server differ from one operating system to another. Please execute only the instructions matching your favorite OS.

If your operating system of choice is **Ubuntu**, please execute the commands that follow.

```bash
apt-get update

apt-get install -y nfs-kernel-server

NFS_USER=nobody:nogroup
```

On the other hand, if you prefer **CentOS**, the commands are as follows.

```bash
systemctl enable nfs-server.service

systemctl start nfs-server.service

NFS_USER=nfsnobody:nfsnobody
```

No matter the OS, the last command created the environment variable `NFS_USER` that defines the user and the group that will use soon to give a directory permissions that will allow any client to write files.

Please note that we are not setting up firewall and that we're assuming that any node can mount the NFS server we're about to set up.

Next, we'll create a directory we'll export and make the NFS user with wide permission own it.

```bash
mkdir /var/nfs/cje -p

chown $NFS_USER /var/nfs/cje
```

We'll need to configure `/etc/exports` file that will be used by the NFS server to decide where to store the files, write mode, whether it should be synched, and so on.

```bash
echo "/var/nfs/cje    *(rw,sync,no_subtree_check)" \
    | tee -a /etc/exports
```

The only thing left is to restart NFS server (if using Ubuntu), or to export NFS table (if using CentOS).

If you're OS of choice is **Ubuntu**, please execute the command that follows.

```bash
systemctl restart nfs-kernel-server
```

**CentOS** users should export NFS table with the command that follows.

```bash
exportfs -a
```

Our NFS server is now up and running. Before we start using it, we'll need a Kubernetes cluster. For now, please exit the VM.

```bash
exit
```