## Simple AirPrint bridge for your local printers
### Purpose
Run a container with CUPS and Avahi (mDNS/Bonjour) so that local printers
on the network can be exposed via AirPrint to iOS/macOS devices.

### Requirements
* the container must (really, really should) have its own, dedicated IP so it does not interfere
with other services listen on the ports required
(macOS: already runs CUPS and mdns, Linux: mostly also already runs CUPS and/or Avahi)

#### Hints
* a shared Windows printer must be accessible by anonymous users (without login)
or you must provide a username and password whithin its device URI (`smb://user:pass@host/printer`)

### Create a container
Create a virtual network bridge to your local network so that a
docker container can have its own IP on your subnet.
```shell script
eth=<network interface> # eth0
mac=<network MAC> # AA:AA:AA:AA:AA
ip link add mac0 link $eth address $mac type macvlan mode bridge
# drop & flush DHCP lease on the interface
dhclient -r $eth && ip addr flush dev $eth;
# delete all existing ARP entries
arp -d -i $eth -a
# get DHCP lease on new bridge (same MAC => same lease)
dhclient mac0; service resolvconf restart;
docker network create --driver macvlan --subnet 192.168.2.0/24 --gateway 192.168.2.1 -o parent=mac0 localnet
```

Now create your cups container with a specific IP on your local subnet
```shell script
cups_ip=192.168.2.100
cups_name=cups.home
docker create --name cups-test --net=localnet --ip=$cups_ip --hostname=$cups_name \
  --privileged --memory=100M \
  -p 137:137/udp -p 139:139/tcp -p 445:445/tcp -p 631:631/tcp -p 5353:5353/udp \
  -e CUPS_USER_ADMIN=admin -e CUPS_USER_PASSWORD=secr3t \
  drpsychick/cups-airprint:latest

# start it
docker start cups-test

# open a shell
docker exec -it cups-test /bin/bash
```

### Adding printers:
#### Command line
```shell script
# search for your printer
lpinfo --make-and-model "Epson Stylus Photo RX" -m
# I chose RX620 for my RX520 and it works fine...
lpadmin -p Epson-RX520 -D "Epson Stylus Photo RX520" -m "gutenprint.5.3://escp2-rx620/expert" -v smb://user:pass@host/Epson-RX520
```
Options:
* `-m <standard PPD model>` - `everywhere`: this seems to work only for `ipp` protocol?!?
```shell script
lpadmin -p Epson-Test -m everywhere -v smb://user:pass@host/Epson-RX520
```

#### Manually through web interface (**you should enabling this only temporarily!**)
`cupds.conf`:
```shell script
Listen $cups_ip:631
WebInterface Yes
<Location />
  Order allow,deny
  Allow from all
</Location>
<Location /admin>
  Order allow,deny
  Allow from all
</Location>
```
Then go to `https://$cups_ip:631/admin`, login and setup your printer(s).

#### Automated through files
This is easiest combined with the webinterface:
1. setup your printer through the webinterface or `lpadmin` and test it
2. take the `printers.conf` and `.ppd` files from the container and automate it
 
 ```shell script
# get `printers.conf` and `.ppd` file from the container
docker cp cups-test:/etc/cups/printers.conf ~/mycups/
docker cp cups-test:/etc/cups/ppd/PrinterName.ppd ~/mycups/
```

Use your own docker image:

`~/mycups/Dockerfile`:
```Dockerfile
FROM drpsychick/cups-airprint:latest

COPY printers.conf /etc/cups/
COPY PrinterName.ppd /etc/cups/ppd
```

And create the container using your own image:
```shell script
docker build -t mycups:latest .
docker create --name cups-real [...] mycups:latest
docker start cups-real
```

### Test it
1. on any iOS device, take any file and tap on share -> print (TODO: add screenshot)
2. on any macOS device, add a new printer. You'll find your printer prefixed with `AirPrint` in the `default` tab
3. on the web interface, select `Print Test Page` in the `Maintenance` dropdown

### Issues:
https://github.com/DrPsychick/docker-cups-airprint/issues

### Hints for QNAP
* using `macvlan` is not possible, instead you should use `qnet` driver to create the docker network
(`docker network create --driver=qnet --ipam-driver=qnet --ipam-opt=iface=bond0 --subnet ...`)

### TODO
* [ ] setup travis pipeline (automatic builds)
* [ ] support ENV configuration
  * webinterface yes/no
  * ssl config
  * per printer: name, location, description, device URI, URL for PPD or model
    * `lpadmin` command (without `.ppd`)
* [ ] make it configurable through ENV incl. `.ppd` support (binary file) - how?
  * background: it would be great if I did not have to create my own image just to configure my printer...
  * Options:
    * mount directory -> requires users to setup persistent storage...
    * install printer on every startup with `lpadmin` -> nice idea!
    * through ENV (one line, BASE64 encoded?) -> veeery ugly
* [ ] fix SSL: #1
* [ ] cleanup and create proper documentation
* [ ] How to get `.ppd` directly for your printer?
