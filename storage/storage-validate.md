# Validating StorageClasses

The section that follows can be used to validate storage of any type.

We'll split the validation into two parts. We'll check whether the StorageClass works when specified explicitly as well as whether it works as the `default` class. The latter is not mandatory for CJE, but it does simplify the installation and setup.

## Validating Explicit StorageClass

We'll deploy a simple StatefulSet that can be used to test storage. Let's take a quick look at the definition.

```bash
curl https://raw.githubusercontent.com/vfarcic/k8s-specs/master/sts/cje-test.yml
```

```yaml
apiVersion: apps/v1beta2
kind: StatefulSet
metadata:
  name: test
spec:
  serviceName: test
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: test
        image: alpine
        command:
          - sleep
          - "1000000"
        volumeMounts:
        - name: test-data
          mountPath: /tmp
  volumeClaimTemplates:
  - metadata:
      name: test-data
      # annotations:
      #   volume.beta.kubernetes.io/storage-class: "cje-storage"
    spec:
      storageClassName: cje-storage
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 2Gi

---

apiVersion: v1
kind: Service
metadata:
  name: test
spec:
  selector:
    app: test
  ports:
  - name: http
    port: 80
    targetPort: 80
    protocol: TCP
```

That definition assumes that the name of the StorageClass we'll use is `cje-storage`. The chances are that you named the StorageClass differently, or that you did not even have a say in namings. We'll remedy the issue by replacing the name using `sed`.

```bash
SC_NAME=[...]

curl https://raw.githubusercontent.com/vfarcic/k8s-specs/master/sts/cje-test.yml \
    | sed -e "s@storageClassName: cje-storage@storageClassName: ${SC_NAME}@g" \
    | kubectl -n cjoc apply -f -
```

Please make sure to replace `[...]` with the name of the StorageClass you'd like to test. If in doubt, list the classes with `kubectl get sc`.

The output should show that the `test` `statefulset` and `service` were `created`.

Next, we'll confirm whether we can write to the drive defined through the ServiceClass.

```bash
kubectl -n cjoc exec test-0 \
    -- touch /tmp/something

kubectl -n cjoc exec test-0 \
    -- ls /tmp
```

The output of the latter command should prove the existence of the file `something` created with the prior command.

Testing whether we can write a file does not prove much. We'd accomplish the same result even if we did not attach a drive. The file would be created inside container's local file system. What really matters is proving that the files are persisted across container and Pod failures.

```bash
kubectl -n cjoc delete pod test-0
```

We deleted the Pod. Since it was created through the StatefulSet, a new Pod will be created in its place. We can confirm that by waiting for a moment or two for StatefulSet to detect the failure and listing all the Pods in the Namespace.

```bash
kubectl -n cjoc get pods
```

The output is as follows.

```
NAME                                      READY     STATUS    RESTARTS   AGE
nfs-client-provisioner-69688c76dd-b2bjj   1/1       Running   0          34m
test-0                                    1/1       Running   0          9s
```

The `test-0` Pod is running again, and we can validate whether the file we created is indeed persisted across failures.

```bash
kubectl -n cjoc exec test-0 \
    -- ls /tmp
```

We should see `something` as the output, thus confirming that the file is indeed persistent on the external drive.

We're finished with a very rudimentary validation which confirmed that explicitly defined StorageClass works. Before we proceed, we'll delete the resources we created.

```bash
kubectl -n cjoc delete \
    -f https://raw.githubusercontent.com/vfarcic/k8s-specs/master/sts/cje-test.yml

kubectl -n cjoc \
    delete pvc test-data-test-0
```

## Validating Default StorageClass

Validation whether a `default` StorageClass works as expected is optional. Feel free to skip this section if you do not think that CJE will use it or if there is a valid reason not to have it. If you do want to proceed and confirm that the `default` StorageClass works, the steps are almost the same as those we executed previously.

We'll deploy a simple StatefulSet that can be used to test storage. Let's take a quick look at the definition.

```bash
curl https://raw.githubusercontent.com/vfarcic/k8s-specs/master/sts/cje-test.yml
```

```yaml
apiVersion: apps/v1beta2
kind: StatefulSet
metadata:
  name: test
spec:
  serviceName: test
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: test
        image: alpine
        command:
          - sleep
          - "1000000"
        volumeMounts:
        - name: test-data
          mountPath: /tmp
  volumeClaimTemplates:
  - metadata:
      name: test-data
      # annotations:
      #   volume.beta.kubernetes.io/storage-class: "cje-storage"
    spec:
      storageClassName: cje-storage
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 2Gi

---

apiVersion: v1
kind: Service
metadata:
  name: test
spec:
  selector:
    app: test
  ports:
  - name: http
    port: 80
    targetPort: 80
    protocol: TCP
```

That definition assumes that the name of the StorageClass we'll use is `cje-storage`. Since we'll use the `default` StorageClass, we'll comment the line with `storageClassName`.

```bash
curl https://raw.githubusercontent.com/vfarcic/k8s-specs/master/sts/cje-test.yml \
    | sed -e "s@storageClassName@# storageClassName@g" \
    | kubectl -n cjoc apply -f -
```

The output should show that the `test` `statefulset` and `service` were `created`.

Next, we'll confirm whether we can write to the drive defined through the ServiceClass.

```bash
kubectl -n cjoc exec test-0 \
    -- touch /tmp/something

kubectl -n cjoc exec test-0 \
    -- ls /tmp
```

The output of the latter command should prove the existence of the file `something` created with the prior command.

Testing whether we can write a file does not prove much. We'd accomplish the same result even if we did not attach a drive. The file would be created inside container's local file system. What really matters is proving that the files are persisted across container and Pod failures.

```bash
kubectl -n cjoc delete pod test-0
```

We deleted the Pod. Since it was created through the StatefulSet, a new Pod will be created in its place. We can confirm that by waiting for a moment or two for StatefulSet to detect the failure and listing all the Pods in the Namespace.

```bash
kubectl -n cjoc get pods
```

The output is as follows.

```
NAME                                      READY     STATUS    RESTARTS   AGE
nfs-client-provisioner-69688c76dd-b2bjj   1/1       Running   0          34m
test-0                                    1/1       Running   0          9s
```

The `test-0` Pod is running again, and we can validate whether the file we created is indeed persisted across failures.

```bash
kubectl -n cjoc exec test-0 \
    -- ls /tmp
```

We should see `something` as the output, thus confirming that the file is indeed persistent on the external drive.

We're finished with a very rudimentary validation which confirmed that explicitly defined StorageClass works. Before we proceed, we'll delete the resources we created.

```bash
kubectl -n cjoc delete \
    -f https://raw.githubusercontent.com/vfarcic/k8s-specs/master/sts/cje-test.yml

kubectl -n cjoc \
    delete pvc test-data-test-0
```

## Measuring Persistent Volume Speed

TODO: Continue

```bash
SC_NAME=[...]

curl https://raw.githubusercontent.com/vfarcic/k8s-specs/master/sts/cje-test.yml \
    | sed -e "s@storageClassName: cje-storage@storageClassName: ${SC_NAME}@g" \
    | kubectl -n cjoc apply -f -
```

```
statefulset.apps "test" created
service "test" created
```

```bash
kubectl -n cjoc \
    exec -it test-0 -- sh
```
