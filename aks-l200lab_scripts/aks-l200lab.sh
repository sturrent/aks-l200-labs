#!/bin/bash

# script name: aks-l200lab.sh
# Version v0.1.7 20200423
# Set of tools to deploy L200 Azure containers labs

# "-g|--resource-group" resource group name
# "-n|--name" AKS cluster name
# "-l|--lab" Lab scenario to deploy
# "-v|--validate" Validate a particular scenario
# "-r|--region" region to deploy the resources
# "-h|--help" help info
# "--version" print version

# read the options
TEMP=`getopt -o g:n:l:r:hv --long resource-group:,name:,lab:,region:,help,validate,version -n 'aks-l200lab.sh' -- "$@"`
eval set -- "$TEMP"

# set an initial value for the flags
RESOURCE_GROUP=""
CLUSTER_NAME=""
LAB_SCENARIO=""
LOCATION="eastus2"
VALIDATE=0
HELP=0
VERSION=0

while true ;
do
    case "$1" in
        -h|--help) HELP=1; shift;;
        -g|--resource-group) case "$2" in
            "") shift 2;;
            *) RESOURCE_GROUP="$2"; shift 2;;
            esac;;
        -n|--name) case "$2" in
            "") shift 2;;
            *) CLUSTER_NAME="$2"; shift 2;;
            esac;;
        -l|--lab) case "$2" in
            "") shift 2;;
            *) LAB_SCENARIO="$2"; shift 2;;
            esac;;
        -r|--region) case "$2" in
            "") shift 2;;
            *) LOCATION="$2"; shift 2;;
            esac;;    
        -v|--validate) VALIDATE=1; shift;;
        --version) VERSION=1; shift;;
        --) shift ; break ;;
        *) echo -e "Error: invalid argument\n" ; exit 3 ;;
    esac
done

# Variable definition
SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
SCRIPT_NAME="$(echo $0 | sed 's|\.\/||g')"
SCRIPT_VERSION="Version v0.1.7 20200423"

# Funtion definition

# az login check
function az_login_check () {
    if $(az account list 2>&1 | grep -q 'az login')
    then
        echo -e "\nError: You have to login first with the 'az login' command before you can run this lab tool\n"
        az login -o table
    fi
}

# check resource group and cluster
function check_resourcegroup_cluster () {
    RG_EXIST=$(az group show -g $RESOURCE_GROUP &>/dev/null; echo $?)
    if [ $RG_EXIST -ne 0 ]
    then
        echo -e "\nCreating resource group ${RESOURCE_GROUP}...\n"
        az group create --name $RESOURCE_GROUP --location $LOCATION &>/dev/null
    else
        echo -e "\nResource group $RESOURCE_GROUP already exists...\n"
    fi

    CLUSTER_EXIST=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME &>/dev/null; echo $?)
    if [ $CLUSTER_EXIST -eq 0 ]
    then
        echo -e "\nCluster $CLUSTER_NAME already exists...\n"
        echo -e "Please remove that one before you can proceed with the lab.\n"
        exit 4
    fi
}

# validate cluster exists
function validate_cluster_exists () {
    CLUSTER_EXIST=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME &>/dev/null; echo $?)
    if [ $CLUSTER_EXIST -ne 0 ]
    then
        echo -e "\nERROR: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP does not exists...\n"
        exit 5
    fi
}

# Lab scenario 1
function lab_scenario_1 () {
    echo -e "Deploying cluster for lab1...\n"
    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --node-count 2 \
    --generate-ssh-keys \
    --tag l200lab=${LAB_SCENARIO} \
    -o table

    validate_cluster_exists

    echo -e "Getting kubectl credentials for the cluster...\n"
    az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing
    
    NODE_RESOURCE_GROUP="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query nodeResourceGroup -o tsv)"
    echo -e "\n\nPlease wait while we are preparing the environment for you to troubleshoot..."
    CLUSTER_NSG="$(az network nsg list -g $NODE_RESOURCE_GROUP --query [0].name -o tsv)"
    az network nsg rule create -g $NODE_RESOURCE_GROUP --nsg-name $CLUSTER_NSG \
    -n SecRule1  --priority 200 \
    --source-address-prefixes VirtualNetwork \
    --destination-address-prefixes Internet \
    --destination-port-ranges "9000" \
    --direction Outbound \
    --access Deny \
    --protocol Tcp \
    --description "Security test" &>/dev/null

    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    kubectl -n kube-system delete po -l component=tunnel &>/dev/null
    echo -e "\n\n********************************************************"
    echo -e "Not able to execute kubectl logs or kubectl exec commands...\n"
    echo -e "Cluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_1_validation () {
    validate_cluster_exists
    LAB_TAG="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query tags.l200lab -o tsv)"
    if [ -z $LAB_TAG ]
    then
        echo -e "\nError: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    elif [ $LAB_TAG -eq 1 ]
    then
        az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
        TUNNEL_STATUS="$(timeout 50 kubectl -n kube-system logs -l component=tunnel &>/dev/null; echo $?)"
        if [ $TUNNEL_STATUS -eq 0 ]
        then
            echo -e "\n\n========================================================"
            echo -e "\nCluster looks good now, the keyword for the assesment is:\n\nSecret Phrase One\n"
        else
            echo -e "\nScenario $LAB_SCENARIO is still FAILED\n"
        fi
    else
        echo -e "\nError: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    fi
}

# Lab scenario 2
function lab_scenario_2 () {
    az aks create --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --node-count 2 \
    --network-plugin azure \
    --generate-ssh-keys \
    --tag l200lab=${LAB_SCENARIO} \
    -o table

    validate_cluster_exists

    az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom # this is the name of the configmap you can overwrite with your changes
  namespace: kube-system
data:
    test.override: |
          hosts/etc/coredns/custom/example.hosts { # example.hosts must be a file
              fallthrough
          }
    example.hosts: |
          10.0.0.1 example.org
          192.168.11.1 pepeluis.com
EOF

    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"

    kubectl -n kube-system delete po -l k8s-app=kube-dns &>/dev/null

    echo -e "\n\n********************************************************"
    echo -e "\nDNS resolution is not working for pods...\n"
    echo -e "Cluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_2_validation () {
    validate_cluster_exists
    LAB_TAG="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query tags.l200lab -o tsv)"
    if [ -z $LAB_TAG ]
    then
        echo -e "\nError: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    elif [ $LAB_TAG -eq $LAB_SCENARIO ]
    then
        az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
        DNS_STATUS=""
        if ! $(kubectl -n kube-system get po -l k8s-app=kube-dns | grep -q CrashLoopBackOff) && $(kubectl -n kube-system get po -l k8s-app=kube-dns | grep -q Running)
        then
            echo -e "\n\n========================================================"
            echo -e "\nCluster looks good now, the keyword for the assesment is:\n\nEvery Cloud Has a Silver Lining\n"
        else
            echo -e "\nScenario $LAB_SCENARIO is still FAILED\n"
        fi
    else
        echo -e "\nError: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    fi
}

# Lab scenario 3
function lab_scenario_3 () {
    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --node-count 2 \
    --generate-ssh-keys \
    --tag l200lab=${LAB_SCENARIO} \
    -o table

    validate_cluster_exists

    az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null

    az network public-ip create -g $RESOURCE_GROUP -n l200lab-testip --allocation-method Static --sku Standard --location $LOCATION -o table
    PUBLIC_IP="$(az network public-ip show -g $RESOURCE_GROUP -n l200lab-testip --query ipAddress -o tsv)"
    NODE_RESOURCE_GROUP="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query nodeResourceGroup -o tsv)"

## LB issues
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-resource-group: $NODE_RESOURCE_GROUP
  name: azure-load-balancer
  namespace: kube-system
spec:
  loadBalancerIP: $PUBLIC_IP
  type: LoadBalancer
  ports:
  - port: 80
  selector:
    app: azure-load-balancer
EOF

    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    echo -e "\n\n********************************************************"
    echo -e "\nCluster has a service called azure-load-balancer in pending state on the kube-system namespace..."
    echo -e "\nCluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_3_validation () {
    validate_cluster_exists
    LAB_TAG="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query tags.l200lab -o tsv)"
    if [ -z $LAB_TAG ]
    then
        echo -e "\nError: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    elif [ $LAB_TAG -eq $LAB_SCENARIO ]
    then
        az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
        PUBLIC_IP="$(az network public-ip show -g $RESOURCE_GROUP -n l200lab-testip --query ipAddress -o tsv)"
        if ! $(kubectl -n kube-system get svc azure-load-balancer | grep -q '<pending>') && $(kubectl -n kube-system get svc azure-load-balancer | grep -q $PUBLIC_IP)
        then
            echo -e "\n\n========================================================"
            echo -e "\nCluster looks good now, the keyword for the assesment is:\n\nAll Greek To Me\n"
        else
            echo -e "\nScenario $LAB_SCENARIO is still FAILED\n"
        fi
    else
        echo -e "\nError: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    fi
}

# Lab scenario 4
function lab_scenario_4 () {
    VNET_NAME="${RESOURCE_GROUP}_vnet"
    SUBNET_NAME="${RESOURCE_GROUP}_subnet"
    az network vnet create \
        --resource-group $RESOURCE_GROUP \
        --name $VNET_NAME \
        --address-prefixes 192.168.0.0/16 \
        --dns-servers 172.20.50.2 \
        --subnet-name $SUBNET_NAME \
        --subnet-prefix 192.168.100.0/24 \
        -o table &>/dev/null
        
        SUBNET_ID=$(az network vnet subnet list \
        --resource-group $RESOURCE_GROUP \
        --vnet-name $VNET_NAME \
        --query [].id --output tsv)

        az aks create \
        --resource-group $RESOURCE_GROUP \
        --name $CLUSTER_NAME \
        --location $LOCATION \
        --kubernetes-version 1.15.7 \
        --node-count 2 \
        --node-osdisk-size 100 \
        --network-plugin azure \
        --service-cidr 10.0.0.0/16 \
        --dns-service-ip 10.0.0.10 \
        --docker-bridge-address 172.17.0.1/16 \
        --vnet-subnet-id $SUBNET_ID \
        --generate-ssh-keys \
        --tag l200lab=${LAB_SCENARIO} \
        -o table

    validate_cluster_exists
    az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null

    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    echo -e "\n\n********************************************************"
    echo -e "\nLab environment is ready. Cluster deployment failed, looks like an issue with VM custom script extention...\n"
    echo -e "\nCluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_4_validation () {
    validate_cluster_exists
    LAB_TAG="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query tags.l200lab -o tsv)"
    if [ -z $LAB_TAG ]
    then
        echo -e "\nError: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    elif [ $LAB_TAG -eq $LAB_SCENARIO ]
    then
        az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
        if $(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query provisioningState -o tsv | grep -q "Succeeded") && $(kubectl get no | grep -q " Ready ")
        then
            echo -e "\n\n========================================================"
            echo -e "\nCluster looks good now, the keyword for the assesment is:\n\nA Piece of Cake\n"
        else
            echo -e "\nScenario $LAB_SCENARIO is still FAILED\n"
        fi
    else
        echo -e "\nError: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    fi    
}

# Lab scenario 5
function lab_scenario_5 () {
    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --node-count 2 \
    --generate-ssh-keys \
    --tag l200lab=${LAB_SCENARIO} \
    -o table

    validate_cluster_exists

    az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
    NODE_RESOURCE_GROUP="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query nodeResourceGroup -o tsv)"

    echo -e "\nCompleting the lab setup..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  labels:
    app: fe-pod
  name: fe-pod-svc
spec:
  ports:
  - port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    app: fe-pod
status:
  loadBalancer: {}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: be-pod
  labels:
    app: be-pod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: be-pod
  template:
    metadata:
      labels:
        app: be-pod
    spec:
      containers:
      - name: be-pod
        imagePullPolicy: Always
        image: sturrent/be-pod:latest
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fe-pod
  labels:
    app: fe-pod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fe-pod
  template:
    metadata:
      labels:
        app: fe-pod
    spec:
      containers:
      - name: fe-pod
        imagePullPolicy: Always
        image: sturrent/fe-pod:latest
        ports:
        - containerPort: 8080
EOF

    echo -e "\n\n========================================================"
    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    echo -e "\n\nCluster has two deployments fe-pod and be-pod. The pod on be-pod is sending data to pod in fe-pod over port 8080."
    echo -e "The data is beeing send every 5 seconds and it has the secret phrase in plain text. Setup a capture on the fe-pod and analyse the tcp stream to get the secret phrase."
    echo -e "Hint: you can use something like https://github.com/eldadru/ksniff to caputer the traffic and analyse the tcp stream with Wireshark.\n"
    echo -e "\nCluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_5_validation () {
    validate_cluster_exists
    LAB_TAG="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query tags.l200lab -o tsv)"
    if [ -z $LAB_TAG ]
    then
        echo -e "\nError: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    elif [ $LAB_TAG -eq $LAB_SCENARIO ]
    then
        az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
        echo -e "\n\n========================================================"
        echo -e "\n\nCluster has two deployments fe-pod and be-pod. The pod on be-pod is sending data to pod in fe-pod over port 8080."
        echo -e "The data is beeing send every 5 seconds and it has the secret phrase in plain text. Setup a capture on the fe-pod and analyse the tcp stream to get the secret phrase."
        echo -e "Hint: you can use something like https://github.com/eldadru/ksniff to caputer the traffic and analyse the tcp stream with Wireshark.\n"
    else
        echo -e "\nError: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    fi
}

#if -h | --help option is selected usage will be displayed
if [ $HELP -eq 1 ]
then
	echo "aks-l200lab usage: aks-l200lab -g <RESOURCE_GROUP> -n <CLUSTER_NAME> -l <LAB#> [-v|--validate] [-r|--region] [-h|--help] [--version]"
    echo -e "\nHere is the list of current labs available:\n
***************************************************************
*\t 1. Kubectl exec and logs commands not working
*\t 2. Pods dns queries failing
*\t 3. LoadBalancer service in pending state
*\t 4. AKS failed deployment
*\t 5. Network capture required
***************************************************************\n"
    echo -e '"-g|--resource-group" resource group name
"-n|--name" AKS cluster name
"-l|--lab" Lab scenario to deploy
"-r|--region" region to create the resources
"-v|--validate" Validate a particular scenario
"--version" print version of aks-l200lab
"-h|--help" help info\n'
	exit 0
fi

if [ $VERSION -eq 1 ]
then
	echo -e "$SCRIPT_VERSION\n"
	exit 0
fi

if [ -z $RESOURCE_GROUP ]; then
	echo -e "Error: Resource group value must be provided. \n"
	echo -e "aks-l200lab usage: aks-l200lab -g <RESOURCE_GROUP> -n <CLUSTER_NAME> -l <LAB#> [-v|--validate] [-r|--region] [-h|--help] [--version]\n"
	exit 7
fi

if [ -z $CLUSTER_NAME ]; then
	echo -e "Error: Cluster name value must be provided. \n"
	echo -e "aks-l200lab usage: aks-l200lab -g <RESOURCE_GROUP> -n <CLUSTER_NAME> -l <LAB#> [-v|--validate] [-r|--region] [-h|--help] [--version]\n"
	exit 8
fi

if [ -z $LAB_SCENARIO ]; then
	echo -e "Error: Lab scenario value must be provided. \n"
	echo -e "aks-l200lab usage: aks-l200lab -g <RESOURCE_GROUP> -n <CLUSTER_NAME> -l <LAB#> [-v|--validate] [-r|--region] [-h|--help] [--version]\n"
    echo -e "\nHere is the list of current labs available:\n
***************************************************************
*\t 1. Kubectl exec and logs commands not working
*\t 2. Pods dns queries failing
*\t 3. LoadBalancer service in pending state
*\t 4. AKS failed deployment
*\t 5. Network capture required
***************************************************************\n"
	exit 9
fi

# lab scenario has a valid option
if [[ ! $LAB_SCENARIO =~ ^[1-5]+$ ]];
then
    echo -e "\nError: invalid value for lab scenario '-l $LAB_SCENARIO'\nIt must be value from 1 to 5\n"
    exit 10
fi

# main
echo -e "\nWelcome to the L200 Troubleshooting sessions
********************************************

This tool will use your internal azure account to deploy the lab environment.
Verifing if you are authenticated already...\n"

# Verify az cli has been authenticated
az_login_check

if [ $LAB_SCENARIO -eq 1 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_1

elif [ $LAB_SCENARIO -eq 1 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_1_validation

elif [ $LAB_SCENARIO -eq 2 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_2

elif [ $LAB_SCENARIO -eq 2 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_2_validation

elif [ $LAB_SCENARIO -eq 3 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_3

elif [ $LAB_SCENARIO -eq 3 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_3_validation

elif [ $LAB_SCENARIO -eq 4 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_4

elif [ $LAB_SCENARIO -eq 4 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_4_validation

elif [ $LAB_SCENARIO -eq 5 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_5

elif [ $LAB_SCENARIO -eq 5 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_5_validation

else
    echo -e "\nError: no valid option provided\n"
    exit 11
fi

exit 0