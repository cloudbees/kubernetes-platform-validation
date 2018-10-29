# Creating StorageClass with NFS Client Provisioner

We already have an NFS server so the next step is to install NFS client as a StorageClass. We'll use [kubernetes nfs-client-provisioner](https://github.com/kubernetes-incubator/external-storage/tree/master/nfs-client). Given that the project provides a Helm Chart, we'll use it as it's the simplest way to install it.

If you do not have Helm client installed on your laptop, please follow the instructions from the [Installing The Helm Client](https://docs.helm.sh/using_helm/#installing-the-helm-client) documentation.

If your cluster does not have Tiller (Helm Server), please execute the commands that follow to install it.

```bash
kubectl create \
    -f https://raw.githubusercontent.com/vfarcic/k8s-specs/master/helm/tiller-rbac.yml \
    --record --save-config

helm init --service-account tiller

kubectl -n kube-system \
    rollout status deploy tiller-deploy
```

We created a ServiceAccount with the required permissions and used it to install `tiller`. The last command validated that it rolled out correctly.

Now we're ready to install NFS Client Provisioner.

```bash
helm install \
  stable/nfs-client-provisioner \
  --name nfs-client-provisioner \
  --namespace kube-system \
  --set nfs.server=$NFS_SERVER_ADDR \
  --set nfs.path=/var/nfs/cje \
  --set storageClass.provisionerName=cloudbees.com/cje-nfs
```

We'll wait until the provisioner rolls out before we proceed.

```bash
kubectl -n kube-system \
  rollout status \
  deployment nfs-client-provisioner
```

The output is as follows.

```
Waiting for rollout to finish: 0 of 1 updated replicas are available...
deployment "nfs-client-provisioner" successfully rolled out
```

Finally, we can run a quick test to validate whether the provisioner works as expected.

```bash
curl https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/test-claim.yaml
```

The output is as follows.

```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: test-claim
  annotations:
    volume.beta.kubernetes.io/storage-class: "managed-nfs-storage"
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Mi
```

We'll create a new PersistentVolumeClaim. But, before we do that, we'll have to use `sed` magic to change the StorageClass to `nfs-client`.

```bash
curl https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/test-claim.yaml \
    | sed -e "s@managed-nfs-storage@nfs-client@g" \
    | kubectl -n cjoc create -f -
```

The output is as follows.

```
persistentvolumeclaim "test-claim" created
```

Now we can create a Pod that will use the claim we just created and validate that NFS provisioner indeed works.

```bash
curl https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/test-pod.yaml
```

The output is as follows.

```
kind: Pod
apiVersion: v1
metadata:
  name: test-pod
spec:
  containers:
  - name: test-pod
    image: gcr.io/google_containers/busybox:1.24
    command:
      - "/bin/sh"
    args:
      - "-c"
      - "touch /mnt/SUCCESS && exit 0 || exit 1"
    volumeMounts:
      - name: nfs-pvc
        mountPath: "/mnt"
  restartPolicy: "Never"
  volumes:
    - name: nfs-pvc
      persistentVolumeClaim:
        claimName: test-claim
```

As you can see, it is a very simple Pod based on `busybox`. It'll create a file `/mnt/SUCCESS`. If that file does not already exist, it'll exit with `0`. The `volumes` section references the `test-claim` we created a few moments ago.

```bash
kubectl create \
    -n cjoc \
    -f https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/test-pod.yaml
```

The output is as follows.

```
pod "test-pod" created
```

Now we can enter the node with our NFS server and confirm that the file was indeed created and that it is in a directory dedicated to the claim.

First, we'll list all the files in the `/var/nfs/cje` directory.

```bash
ssh -i cje root@$NFS_SERVER_ADDR \
    "ls -l /var/nfs/cje"
```

The output is as follows.

```
drwxrwxrwx. 2 nfsnobody nfsnobody 21 Jun  7 00:44 cjoc-test-claim-pvc-d5fa9106-69eb-11e8-b65a-ea9238c4f6a5
```

We can see that the provisioner created a directory `cjoc-test-claim-pvc-d5fa9106-69eb-11e8-b65a-ea9238c4f6a5` dedicated to the claim.

Let's chech the files in the new directory.

```bash
ssh -i cje root@$NFS_SERVER_ADDR \
    "ls -l /var/nfs/cje/cjoc-test*"
```

The output is as follows.

```
-rw-r--r--. 1 nfsnobody nfsnobody 0 Jun  7 00:44 SUCCESS
```

We can see that the `SUCCESS` file we created inside the Pod is now stored in the NFS server.

Let's see what happens if we delete the Pod and the Claim.

```bash
kubectl delete \
    -n cjoc \
    -f https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/test-pod.yaml

kubectl delete \
    -n cjoc \
    -f https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/test-claim.yaml
```

The combined output of the two commands is as follows.

```
pod "test-pod" deleted

persistentvolumeclaim "test-claim" deleted
```

Let's see, one more time, the contents of the `/var/nfs/cje` directory inside the node hosting the NFS server.

```bash
ssh -i cje root@$NFS_SERVER_ADDR \
    "ls -l /var/nfs/cje"
```

The output is as follow.

```
drwxrwxrwx. 2 nfsnobody nfsnobody 21 Jun  7 00:44 archived-cjoc-test-claim-pvc-d5fa9106-69eb-11e8-b65a-ea9238c4f6a5
```

Please note that the directory was renamed by adding `archived-` prefix. We can see that the directories dedicated to claims are archived when the claim is deleted