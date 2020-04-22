#!/bin/bash

## Script to convert the base lab scripts to binaries

SHC_STATUS=$(which shc > /dev/null; echo $?)
if [ $SHC_STATUS -ne 0 ]
then
    echo -e "\nError: missing shc binary...\n"
    exit 4
fi

aks-l200lab_SCRIPTS="$(ls ./aks-l200lab_scripts/)"
if [ -z "$aks-l200lab_SCRIPTS" ]
then
    echo -e "Error: missing aks-l200lab scripts...\n"
    exit 5
fi

function convert_to_binary() {
    SCRIPT_NAME="$1"
    BINARY_NAME="$(echo "$SCRIPT_NAME" | sed 's/.sh//')"
    shc -f ./aks-l200lab_scripts/${SCRIPT_NAME} -r -o ./aks-l200lab_binaries/${BINARY_NAME}
    rm -f ./aks-l200lab_scripts/${SCRIPT_NAME}.x.c > /dev/null 2>&1
}

for FILE in $(echo "$aks-l200lab_SCRIPTS")
do
    convert_to_binary $FILE
done

exit 0
