<h1 align="left">Apache Atlas Installation with Ansible</h1>

###

<p align="left">This Ansible playbook automates the installation and configuration of Apache Atlas 2.4.0 on a single-node Ubuntu machine, integrated with an existing HBase 2.5.5 installation. It’s designed to run as the gadet user with sudo privileges, installing Atlas in /opt/apache-atlas-2.4.0/ and configuring it to use an external HBase instance while managing a local Solr instance.</p>

###

<h2 align="left">Run the Playbook</h2>

###

<p align="left">ansible-playbook install_atlas.yml -K  -vvv</p>

###
