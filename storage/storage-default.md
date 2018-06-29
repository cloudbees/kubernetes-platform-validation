# Making A StorageClass Default

To simplify the processes, you might want to mark one of the StorageClasses as default.

The first step is to identify the name of the StorageClass we'd like to mark as default.

```bash
kubectl get sc
```

The output will vary from one case to another. Please pick the StorageClass you'd like to make default, and replace `[...]` in the command that follows with the name.

```bash
SC_NAME=[...]
```

Next, we'll apply a `patch` that will add the annotation that makes the StorageClass default.

```bash
kubectl patch sc $SC_NAME \
    -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

The output is as follows.

```
storageclass.storage.k8s.io "cje-storage" patched
```

Finally, we'll validate that the StorageClass is indeed marked as `default` by listing all the available classes.

```bash
kubectl get sc
```

The output is as follows.

```
NAME                  PROVISIONER           AGE
cje-storage (default) cloudbees.com/cje-nfs 9m
```

You might have more than one StorageClass and the output is likely to be different. What matters is that the class you chose to convert to `default` has `(default)` next to its name.