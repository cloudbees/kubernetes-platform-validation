# Validating RBAC

In this section, we'll validate whether RBAC is configured correctly. Specifically, we'll check whether Pods are denied the right to communicate with KubeAPI with proper service accounts.

We'll start by creating two namespaces.

```bash
kubectl create ns test1

kubectl create ns test2
```

Assuming that RBAC is properly set up (we'll test that soon), we'd need to create a few service accounts that will allow processes running inside Pods in those namespaces, communicate with Kube API. As a test, we'll define roles that will allow us to do almost any Pod-related operation from within another Pod. At the same time, we'll need to confirm that we are not allowed to create Pods (or any other Kubernetes resource) in any other Namespace.

Let's take a quick look at a definition that creates a service account, a few roles, and a few role bindings.

```bash
curl https://raw.githubusercontent.com/vfarcic/k8s-specs/master/sa/pods-all.yml
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pods-all
  namespace: test1

---

kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: pods-all
  namespace: test1
rules:
- apiGroups: [""]
  resources: ["pods", "pods/exec", "pods/log"]
  verbs: ["*"]

---

kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: pods-all
  namespace: test2
rules:
- apiGroups: [""]
  resources: ["pods", "pods/exec", "pods/log"]
  verbs: ["*"]

---

apiVersion: rbac.authorization.k8s.io/v1beta1
kind: RoleBinding
metadata:
  name: pods-all
  namespace: test1
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pods-all
subjects:
- kind: ServiceAccount
  name: pods-all

---

apiVersion: rbac.authorization.k8s.io/v1beta1
kind: RoleBinding
metadata:
  name: pods-all
  namespace: test2
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pods-all
subjects:
- kind: ServiceAccount
  name: pods-all
  namespace: test1
```

The ServiceAccount `pods-all` will be created in the Namespace `test1`. As a result, only the Pods in the same Namespace will be able to use it.

Further on, we have two Roles named `pods-all`. Their specs are the same except for the fact that one is in the Namespace `test1`, and the other in `test2`. The permissions behind those roles provide the ability to do almost any operation on Pods, and no other resource type.

Finally, the last two resources are RoleBindings. Each references the Role `pods-all` in their respective Namespaces. The major difference is that the second RoleBinding is in the Namespace `test2` but it relates to the ServiceAccount `pods-all` in the Namespace `test1`.

As a result of that definition, we should be able to create Pods in the Namespace `test1` and from within the containers in those Pods, create new Pods, output their logs, and so on. Any Pod operation within the two Namespaces initiated through a process in a Pod running inside the Namespace `test1` should be allowed. RBAC works in a way that we specify only what is allowed, and not what isn't. So, any other operation should not be allowed.

Let's apply the resources from the `pods-all.yml` file.

```bash
kubectl apply \
    -f https://raw.githubusercontent.com/vfarcic/k8s-specs/master/sa/pods-all.yml
```

The output is as follows.

```
serviceaccount "pods-all" created
role "pods-all" created
role "pods-all" created
rolebinding "pods-all" created
rolebinding "pods-all" created
```

Next, we'll create a Pod that will allow us to test the assumptions. Let's take a look at the definition first.

```bash
curl https://raw.githubusercontent.com/vfarcic/k8s-specs/master/sa/kubectl-test2.yml
```

The output is as follows.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: kubectl
  namespace: test1
spec:
  serviceAccountName: pods-all
  containers:
  - name: kubectl
    image: vfarcic/kubectl
    command: ["sleep"]
    args: ["100000"]
```

It defines a Pod with a container based on `vfarcic/kubectl` image. It contains `kubectl` that will allow us (or not) to spin up additional Pods. The Pod uses the ServiceAccount `pods-all` and will run in the namespace `test1`.

Let's apply the definition.

```bash
kubectl apply \
    -f https://raw.githubusercontent.com/vfarcic/k8s-specs/master/sa/kubectl-test2.yml
```

Please wait a few moments until the image is pulled and the Pod is up-and-running.

Next, we'll enter into the container that forms the Pod.

```bash
kubectl -n test1 exec -it kubectl -- sh
```

Can we create a Pod in the `test2` Namespace? Let's see.

```bash
kubectl -n test2 \
    run new-test \
    --image=alpine \
    --restart=Never \
    sleep 10000
```

The output is as follows.

```
pod "new-test" created
```

Judging by the output, the Pod was created and, therefore, our ServiceAccount has the sufficient permissions.

Can we list the Pods in the `test2` Namespace?

```bash
kubectl -n test2 get pods
```

The output is as follows.

```
NAME     READY STATUS  RESTARTS AGE
new-test 1/1   Running 0        17s
```

Checking only the operations were should be allowed to execute gives us only part of the picture. Those commands do not prove that we are NOT allowed to issue requests to Kube API outside of those specified in the Roles. To test that, we'll try to create a Pod outside Namespaces `test1` and `test2`.

```bash
kubectl -n default get pods
```

The output is as follows.

```
Error from server (Forbidden): pods is forbidden: User "system:serviceaccount:test1:pods-all" cannot list pods in the namespace "default"
```

That confirms that the ServiceAccount `pods-all cannot list pods in the namespace "default"`.

We're done with a quick RBAC validation. We'll exit the `kubectl` Pod and delete the test Namespaces.

```bash
exit

kubectl delete ns test1 test2
```