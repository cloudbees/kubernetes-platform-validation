## Creating A Rancher Droplet

We'll need a DigitalOcean token that will allow us to authenticate with its API. Please open the API Tokens screen.

```bash
open "https://cloud.digitalocean.com/settings/api/tokens"
```

> If you are a **Windows user**, you might not be able to use `open` command to interact with your browser. If that's the case, please replace `open` with `echo`, copy the output, and paste it into a new tab of your favorite browser.

Please type *cje* as the token name and click the *Generate Token* button. This is the first and the last time you will be able to see the token through DigitalOcean UI. Please store it somewhere safe. We'll need it soon.

Next, we'll create an SSH key that will allow us to enter into the virtual machines we'll create soon.

Please execute the command that follows.

```bash
ssh-keygen -t rsa
```

Please type `cje` as the file name. Feel free to answer to all the other question with the enter key.

Now that we have the SSH key, we can upload it to DigitalOcean. But, before we do that, we need to authenticate first.

```bash
doctl auth init
```

If this is the first time you're using `doctl`, you will be asked for the authentication token we created earlier.

The output should be similar to the one that follows.

```
Using token [...]

Validating token... OK
```

We can upload the SSH key with the `ssh-key create` command.

Please execute the command the follows.

```bash
doctl compute ssh-key create cje \
    --public-key "$(cat cje.pub)"
```

We created a new SSH key in DigitalOcean and named it `cje`. The content of the key was provided with the `--public-key` argument.

The output should be simialr to the one that follows.

```
ID       Name FingerPrint
21418650 cje  28:f8:51:f0...
```

We'll need the ID of the new key. Instead of copying and pasting it from the output, we'll execute a query that will retrieve the ID from DigitalOcean. That way, we can retrieve it at any time instead of saving the output of the previous command.

```bash
KEY_ID=$(doctl compute ssh-key list \
    | grep cje \
    | awk '{print $1}')

echo $KEY_ID
```

We executed `ssh-key list` command that retrieve all the SSH keys available in our DigitalOcean account. Further on, we used `grep` to filter the result so that only the key named `cje` is output. Finally, we used `aws` to output only the first colume that contains the ID we're looking for.

The output of the latter command should be similar to the one that follows.

```
21418650
```

Next, we need to find out the ID of the image we'll use to create a VM that will host Rancher.

If your operating system of choice is **Ubuntu**, please execute the command that follows.

```bash
DISTRIBUTION=ubuntu-18-04-x64
```

Otherwise, if you prefer **CentOS**, the command is as follows.

```bash
DISTRIBUTION=centos-7-x64
```

Now matter which operating system we prefer, the important thing to note is that we have the environment variable `DISTRIBUTION` that holds the `slug` we can use to find out the ID of the image we'll use. Slag is DigitalOcean term that, in this context, describes the name of a distribution.

Now we can retrieve the ID of the image we'll use.

```bash
IMAGE_ID=$(doctl compute \
    image list-distribution \
    -o json \
    | jq ".[] | select(.slug==\"$DISTRIBUTION\").id")

echo $IMAGE_ID
```

The command retrieved the list of all the distributions and sent the output to `jq` which, in turn, filtered it so that only the ID of the image that matches our desired distribution is retrieved.

The output of the latter command should be similar to the one that follows.

```
34487567
```

Now we are finally ready to create a new VM that will soon how our Rancher server.

```bash
doctl compute droplet create rancher \
    --enable-private-networking \
    --image $IMAGE_ID \
    --size s-2vcpu-4gb \
    --region nyc3 \
    --ssh-keys $KEY_ID
```

We executed a `compute droplet command` that created a Droplet (DigitalOcean name for a node or a VM). We named it `rancher`, enabled private networking, and set the image to the ID we retrieved previously. We used `s-2vcpu-4gb` VM size that provides 2 CPUs and 4 GB RAM. The server will run in New York 3 region for no particular reason besides the fact that we had to choose one. Finally, we specify the SSH key ID we retrieved earlier so that we can enter into the newly created VM and complete the installation.

The output is as follows.

```
ID       Name Public IPv4 Private IPv4 Public IPv6 Memory VCPUs Disk Region Image            Status Tags Features Volumes
96650503 rancher                                   4096   2     80   nyc1   Ubuntu 18.04 x64 new
```

Please note that your ID will be different as we'll as the `Image` if you chose CentOS as your operating system of choice.

Next, we need to retrieve the IP of the new droplet (VM).

Please execute the command the follows.

```bash
RANCHER_IP=$(doctl compute droplet list \
    -o json | \
    jq -r '.[] | select(.name=="rancher").networks.v4[0].ip_address')

echo $RANCHER_IP
```

We retrieved the list of all the droplets (VMs) in JSON format and sent the output to `jq`. It filtered the results so that only `rancher` is retrieved and output the IP address. We stored the final output as `RAnCHER_IP` variable.

The output of the latter command will differ from one case to another. Mine is as follows.

```
208.68.39.72
```