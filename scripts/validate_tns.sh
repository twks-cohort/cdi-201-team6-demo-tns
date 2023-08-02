#!/usr/bin/env bash
set -e

export CLUSTER=$1
export ENVIRONMENT=$(cat environments/${CLUSTER}.json | jq -r .environment)
export NAMESPACE=tns-cloud-$ENVIRONMENT
export HOSTNAME=$(kubectl get svc -n istio-system -l istio=ingressgateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
NAMESPACE=$NAMESPACE HOSTNAME=$HOSTNAME bats --verbose-run test
