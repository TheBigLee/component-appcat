#!/bin/sh
set -e
kubectl -n ${TARGET_NAMESPACE} delete sgdbops securitymaintenance || true
cat <<EOF | kubectl create -f -
apiVersion: stackgres.io/v1
kind: SGDbOps
metadata:
  name: securitymaintenance
  namespace: ${TARGET_NAMESPACE}
spec:
  sgCluster: ${TARGET_INSTANCE}
  op: securityUpgrade
  maxRetries: 1
  securityUpgrade:
    method: InPlace
EOF
