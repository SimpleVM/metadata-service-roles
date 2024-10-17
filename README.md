# Metadata Services Ansible Role

This Ansible role enables the installation and setup of the [SimpleVM Metadata-Server](https://github.com/deNBI/simplevm-metadata-server) related services on machines. To fully utilize the features enabled by this role, a corresponding server needs to be running.
chaaaange
## Installation
```yaml

roles:
  - name: enable_metadata_services
    src: https://github.com/deNBI/metadata-service-roles.git
    scm: git
    version: 1.0.0
```

~~~bash
ansible-galaxy install -r requirements.yml
~~~

## Usage
```yaml
---
roles:
  - name: enable_metadata_services
```


## Features and Function

### Userdata

This role enables the virtual machines within the network of the metadata server to retrieve user data.

#### SSH Keys

The public keys retrieved from the server are set in the corresponding authorization files which then allow ssh-connections to the machine via the corresponding private keys. The daemon implemented with this role synchronizes the keys in the authorization files with the keys given from the server. The settings in the sshd-config get adjusted accordingly.

## General information

### Version checking

All scripts used to retrieve information from the server are versioned, which also holds for the data issued by the metadata server itself.
The `check_version.sh` script is used in all scripts executed in the course of the installed services to ensure compatibility between the services and the data retrieved.
