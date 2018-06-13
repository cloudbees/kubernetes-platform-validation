# Validating Load Balancer And Ingress

We'll deploy a sample application which we'll use only to validate whether the LB and Ingress work as expected.

Let's take a quick look at its definition.

```bash
curl https://raw.githubusercontent.com/vfarcic/k8s-specs/master/ingress/go-demo-2.yml
```

The output, limited to the Ingress resource, is as follows.

```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: go-demo-2
  annotations:
    ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  rules:
  - http:
      paths:
      - path: /demo
        backend:
          serviceName: go-demo-2-api
          servicePort: 8080
```

Any request that enters the cluster and with the path that starts with `/demo`, will be forwarded to the `go-demo-2-api` Service. For a request to enter the cluster, it'll have to be forwarded by the LB. So, the flow of a request should be DNS > external LB > one of the worker nodes > Ingress service > `go-demo-2-api` Service > `go-demo-2-api` Pods.

Let's apply the definition.

```bash
kubectl apply \
    -f https://raw.githubusercontent.com/vfarcic/k8s-specs/master/ingress/go-demo-2.yml
```

The output is as follows.

```
ingress "go-demo-2" created
deployment "go-demo-2-db" created
service "go-demo-2-db" created
deployment "go-demo-2-api" created
service "go-demo-2-api" created
```

We can see that Ingress, the Services, and the Deployments were created. Now we should wait until the Deployment rolls out.

```bash
kubectl rollout status \
    deploy go-demo-2-api
```

The output is as follows.

```
Waiting for rollout to finish: 0 of 3 updated replicas are available...
Waiting for rollout to finish: 1 of 3 updated replicas are available...
Waiting for rollout to finish: 2 of 3 updated replicas are available...
deployment "go-demo-2-api" successfully rolled out
```

With the application up-and-running, we can validate that everything works by sending a request to the external LB.

```bash
curl -i "http://$LB_ADDR/demo/hello"
```

The output is as follows.

```
HTTP/1.1 200 OK
Server: nginx/1.13.8
Date: Thu, 07 Jun 2018 00:30:51 GMT
Content-Type: text/plain; charset=utf-8
Content-Length: 14
Connection: keep-alive
Strict-Transport-Security: max-age=15724800; includeSubDomains;

hello, world!
```

By receiving the response code `200` and getting the `hello, world!` message, we confirmed that one of the paths works correctly. However, that does not mean that forwarding is limited only to the `/demo` base path. Maybe we made a mistake and Ingress forwards all requests to the `go-demo-2-api` Service. Let's confirm that other paths are not being handled by Ingress or, at least, that they are not forwarded to the `go-demo-2-api` Service.

```bash
curl -i "http://$LB_ADDR/this/does/not/exist"
```

The output is as follows.

```
HTTP/1.1 404 Not Found
Server: nginx/1.13.8
Date: Thu, 07 Jun 2018 00:31:23 GMT
Content-Type: text/plain; charset=utf-8
Content-Length: 21
Connection: keep-alive
Strict-Transport-Security: max-age=15724800; includeSubDomains;

default backend - 404
```

We got a `404` status from nginx with a message `default backend - 404`. Nginx Ingress is configured to return that response whenever none of the Ingress rules match a request. It is catch-all response. By receiving this message, we confirmed that only the requests with the base path `/demo` are forwarded to the `go-demo-2-api` Service.

Ingress is working and we do not need the test application any more. We'll remove the resources we created.

```bash
kubectl delete \
    -f https://raw.githubusercontent.com/vfarcic/k8s-specs/master/ingress/go-demo-2.yml
```

```
ingress "go-demo-2" deleted
deployment "go-demo-2-db" deleted
service "go-demo-2-db" deleted
deployment "go-demo-2-api" deleted
service "go-demo-2-api" deleted
```