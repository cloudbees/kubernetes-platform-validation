# Creating StorageClass with NFS Client Provisioner

We already have an NFS server so the next step is to install NFS client as a StorageClass. We'll use [kubernetes nfs-client-provisioner](https://github.com/kubernetes-incubator/external-storage/tree/master/nfs-client).

Since the provisioner will need to interact with Kube API and we have RBAC enabled, the first step is to create a ServiceAccount.

```bash
curl https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/auth/serviceaccount.yaml
```

The output is as follows.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nfs-client-provisioner
```

There's not much mistery in that ServiceAccount, so we'll go ahead and install it in the `cjoc` Namespace.

```bash
kubectl -n cjoc create \
    -f https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/auth/serviceaccount.yaml
```

The output is as follows.

```
serviceaccount "nfs-client-provisioner" created
```

Since ServiceAccount is useless by itself, we'll need a Role that will provide enough permissions.

```bash
curl https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/auth/clusterrole.yaml
```

The output is as follows.

```yaml
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: nfs-client-provisioner-runner
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["list", "watch", "create", "update", "patch"]
```

We're creating a ClusterRole so that it can be reused for multiple NFS-related ServiceAccounts. It gives wide permissions for `persistentvolumes`, `persistentvolumeclaims`, and `events`, and read-only permissions for `storageclasses`.

Let's create the ClusterRole.

```bash
kubectl create \
    -f https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/auth/clusterrole.yaml
```

The output is as follows.

```
clusterrole "nfs-client-provisioner-runner" created
```

Finally, we need to connect the ServiceAccount with the ClusterRole.

```bash
curl https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/auth/clusterrolebinding.yaml
```

The output is as follows.

```yaml
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: run-nfs-client-provisioner
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
    namespace: default
roleRef:
  kind: ClusterRole
  name: nfs-client-provisioner-runner
  apiGroup: rbac.authorization.k8s.io
```

That resource will bind the ClusterRole to the ServiceAccount. However, it has a slight problem. The Namespace is hard-coded. It assumes that the ServiceAccount is in the `default` Namespace while we created it in `cjoc`. We'll use  `sed` to modify it on-the-fly.

```bash
curl https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/auth/clusterrolebinding.yaml \
    | sed -e "s@namespace: default@namespace: cjoc@g" \
    | kubectl create -f -
```

The output is as follows.

```
clusterrolebinding "run-nfs-client-provisioner" created
```

Now we're ready to create the provisioner.

```bash
curl https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/deployment.yaml
```

The output is as follows.

```yaml
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: nfs-client-provisioner
spec:
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: nfs-client-provisioner
    spec:
      serviceAccountName: nfs-client-provisioner
      containers:
        - name: nfs-client-provisioner
          image: quay.io/external_storage/nfs-client-provisioner:latest
          volumeMounts:
            - name: nfs-client-root
              mountPath: /persistentvolumes
          env:
            - name: PROVISIONER_NAME
              value: fuseim.pri/ifs
            - name: NFS_SERVER
              value: 10.10.10.60
            - name: NFS_PATH
              value: /ifs/kubernetes
      volumes:
        - name: nfs-client-root
          nfs:
            server: 10.10.10.60
            path: /ifs/kubernetes
```

That Deployment will register itself as a provisioner. It'll mount an NFS volume. Later on, we'll create a StorageClass that will use that provisioner which, in turn, will give each StorageClaim a separate directory inside that volume.

You'll notice that quite a few things are hard-coded. We'll need to change the address of the server (`10.10.10.60`), the directory in the NFS server `/ifs/kubernetes`, as well as the name of the provisioner (`fuseim.pri/ifs`). It's important that the latter is unique since both the provisioner and the StorageClass are global so we cannot tie them to the `cjoc` Namespace. Since the idea is to use the NFS server dedicated to Jenkins, we need to keep the option of having other provisioners for other applications.

Let's install it.

```bash
curl https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/deployment.yaml \
    | sed -e "s@10.10.10.60@$NFS_SERVER_ADDR@g" \
    | sed -e "s@/ifs/kubernetes@/var/nfs/cje@g" \
    | sed -e "s@fuseim.pri/ifs@cloudbees.com/cje-nfs@g" \
    | kubectl -n cjoc create -f -
```

The output is as follows.

```
deployment "nfs-client-provisioner" created
```

We'll wait until the provisioner rolls out before we proceed.

```bash
kubectl -n cjoc \
    rollout status \
    deploy nfs-client-provisioner
```

The output is as follows.

```
Waiting for rollout to finish: 0 of 1 updated replicas are available...
deployment "nfs-client-provisioner" successfully rolled out
```

We're missing only one more resource. We need to create a StorageClass that will use the provisioner we just installed.

```bash
curl https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/class.yaml
```

The output is as follows.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-nfs-storage
provisioner: fuseim.pri/ifs # or choose another name, must match deployment's env PROVISIONER_NAME'
```

The StorageClass is fairly straightforward. It delegates all the heavy lifting to the provisioner. We just need to make sure that the `name` is meaningful for our use-case and that the `provisioner` matches the one we created previously.

```bash
curl https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/class.yaml \
    | sed -e "s@managed-nfs-storage@cje-storage@g" \
    | sed -e "s@fuseim.pri/ifs@cloudbees.com/cje-nfs@g" \
    | kubectl -n cjoc create -f -
```

The output is as follows.

```
storageclass "cje-storage" created
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

We'll create a new PersistentVolumeClaim. But, before we do that, we'll have to use `sed` magic to change the StorageClass to `cje-storage`.

```bash
curl https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/nfs-client/deploy/test-claim.yaml \
    | sed -e "s@managed-nfs-storage@cje-storage@g" \
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