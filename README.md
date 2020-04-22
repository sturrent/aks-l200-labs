# AKS-L200lab

This is a set of scripts and tools use to generate a docker image that will have the aks-l200lab binary used to evaluate your AKS troubleshooting skill.

It uses the shc_script_converter.sh (build using the following tool https://github.com/neurobin/shc) to abstract the lab scripts on binary format and then the use the Dockerfile to pack everyting on a Ubuntu container with az cli and kubectl.

Any time the L200 lab scripts require an update the github actions can be use to trigger a new build and push of the updated image.
This will take care of building a new script binary as well as new docker image that will get pushed to the corresponding registry.
The actions will get triggered any time a new release gets published.

Here is the general usage for the image and aks-l200lab tool:

Run in docker
```docker run -it sturrent/aks-l200lab:latest```

AKS-L200lab tool usage
```
$ aks-l200lab -h
aks-l200lab usage: aks-l200lab -g <RESOURCE_GROUP> -n <CLUSTER_NAME> -l <LAB#> [-v|--validate] [-r|--region] [-h|--help] [--version]

Here is the list of current labs available:

***************************************************************
*        1. Kubectl exec and logs commands not working
*        2. Pods dns queries failing
*        3. LoadBalancer service in pending state
*        4. AKS failed deployment
*        5. Network capture required
***************************************************************

"-g|--resource-group" resource group name
"-n|--name" AKS cluster name
"-l|--lab" Lab scenario to deploy
"-r|--region" region to create the resources
"-v|--validate" Validate a particular scenario
"--version" print version of aks-l200lab
"-h|--help" help info
```
