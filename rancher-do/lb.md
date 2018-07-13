# Creating A DigitalOcean Load Balancer

We'll use DigitalOcean Load Balancer. It is a good use case since it needs to be configured manually and thus the logic behind it is similar to the logic we'd use to set up nginx, HAProxy, or F5 as the external LB.

The first step is to find out the IDs of the worker nodes that should be included in the LBs algorithm.

```
WORKER_IDS=$(doctl compute \
    droplet list -o json | \
    jq -r '.[] | select(.name | startswith("worker")).id' \
    | tr '\n' ',' | tr -d ' ')

echo $WORKER_IDS
```

The output of the latter command should be similar to the one that follows.

```
104.131.98.145,104.236.49.97,104.131.106.27,
```

We'll need to remove the trailing comma (`,`) to make it a valid value for the later use.

```bash
WORKER_IDS=${WORKER_IDS: :-1}

echo $WORKER_IDS
```

The output of the latter command should be similar to the one that follows.

```
104.131.98.145,104.236.49.97,104.131.106.27
```

The only difference is that the comma (`,`) at the end is no more.

Next, we need to find out the port of the Service that makes the Ingress proxy accessible from outside the cluster.

```bash
HTTP_PORT=$(kubectl -n ingress-nginx \
    get svc ingress-nginx \
    -o jsonpath="{.spec.ports[?(@.name==\"http\")].nodePort}")

echo $HTTP_PORT
```

We filtered the JSON output to retrieve only the `nodePort`. Normally, you'd retrieve not only `http`, but also `https` port. However, since you might not have a certificate at hand, we'll skip HTTPS.

Now that we have the IDs of all the worker nodes, we can proceed and create a load balancer.

```bash
doctl compute load-balancer create \
    --droplet-ids $WORKER_IDS \
    --forwarding-rules "entry_protocol:tcp,entry_port:80,target_protocol:tcp,target_port:$HTTP_PORT" \
    --health-check protocol:http,port:$HTTP_PORT,path:/healthz,check_interval_seconds:10,response_timeout_seconds:5,healthy_threshold:5,unhealthy_threshold:3 \
    --name cje \
    --region nyc3
```

We created an LB in `nyc3` region (the same one where the cluster nodes are).

The forwarding rules will pass requests entering on the port `80` (HTTP) to the same port on one of the worker nodes. In a "real-world" situation, we'd add SSL certificates to the load balancer and forward `443` (HTTPS) requests as well.

The health checks will ping `/healtz` endpoint every ten seconds. If a valid response (`200`) is not received within five seconds, the node will be excluded from the algorithm.

If you're wondering where does `/healtz` endpoint come from, it was created by the Ingress controller and it is available through the Ingress Service on every node of the cluster.

Now that we have the LB, we should retrieve its IP.

```bash
LB_IP=$(doctl compute load-balancer \
    list -o json | jq -r '.[0].ip')

echo $LB_IP
```

The output of the latter command should be a valid IP

The last step will be to create a domain. Since I cannot be sure whether you have a "real" domain at hand, we'll create one using [nip.io](http://nip.io/).

```bash
LB_ADDR=$LB_IP.nip.io
```

Now that we have the domain we can use to access the LB, we can proceed and validate whether the load balancer and Ingress work correctly.
