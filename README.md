# Upgrading mssql server in bootc

## Purpose

This repo shows an example of how to build a mssql-server bootc image  
It can build version 15.x and 16.x of mssql-server  
The idea is to demonstrate how to run an upgrade in an immutable bootc system  
We use [Orchard Core CMS](https://orchardcore.net/) to create a new blog, and prove that the upgrade works as expected  
Everything is scripted via Makefile, in case you want to check the actual command that runs for a specific step, just run:  
```
make -n name-of-the-step
```

I adapted the Containerfiles that [@ckyrouak](https://github.com/ckyrouac) has in his https://github.com/ckyrouac/bootc-mssql-examples repository to suit my needs

## Customize environment

- The first lines of the `Makefile` contain the variables more prone to be customized. You can edit the `Makefile` or create a new file called `.env` to set your custom variables there
- Update `config.toml` to add your ssh public key
- Make sure `DB_HOST` exists in DNS

## Steps

- Build a container image and disk image with mssql-server 15.x  
First step is to build a bootc container image with mssql 15.x installed  
We also need to build a qcow2 disk image that we will use to provision a VM  

```
make image disk MSSQL_VERSION=15
```

- Provision a VM  
We use libvirt to provision a new VM with the disk image we built before  
```
make vm MSSQL_VERSION=15
```

- Create a database and credentials for Orchard Core CMS  
Once the VM starts, we should create a username and a database that will be used by the Orchard Core CMS  
```
make orchard-db-init
```

- Start a containerized version of Orchard Core  
Now we will start the CMS. It will output a connection string that we will use on the next step  
```
make orchard-start
```

- Create a blog in Orchard Core  
We will go to http://localhost:8080 (or wherever you started the orchard core container) and proceed to create a new site, using the `Blog` template  
Select `Sql Server` as database engine, and provide the connection string that we got in the previous step  

- Play a bit with the blog  
We can add a few entries to the blog, via http://localhost:8080/admin  

- Create a mssql-server 16.x bootc container image, and push it to a container registry  
We will be using that image to upgrade the VM that holds the running database  
```
make image push MSSQL_VERSION=16
```

- Upgrade the VM using `bootc switch`  
```
make bootc-switch MSSQL_VERSION=16
```

- Wait for VM to reboot, and check that everything is in place  
We have successfully upgraded an immutable RHEL image mode to an image using bootc switch  
Check that the blog is still in place, all the posts are present, and you can create new ones  
