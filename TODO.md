TASKS:
- Run and validate health-check.sh 
- Delete configuration creation from Dockerfile. `configure-service.sh` script called from `entrypoint.sh` converts config templates into proper config files and replaces templates with environment variable value. Config templates, located in ./configs should be volume mounted to the container. Validate this !
- Is DNS check part of health-check.sh script? If not, update it.
- Is DHCP check part of health-check.sh script? If not, update it.
- Is TFTP check part of health-check.sh script? If not, update it.
- Is HTTP check part of health-check.sh script? If not, update it.
- Is setup.sh script calls health-check.sh script as part of setup validation process? If not, include health-check.sh script as part of setup.sh script
- Is setup.sh script calls configure-service.sh script? If not, include configure-service.sh as part of setup.sh script to be called before podman starts the main container.
