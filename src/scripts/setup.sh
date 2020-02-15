set -xueo pipefail

BUILD_TAG="runbook-<%= @job_id %>"
NS="<%= @k8s.namespace %>"
IMAGE="<%= @k8s.image %>"
SECRET="<%= @k8s.secret %>"

cleanup() {
  # Teardown pod
  kubectl -n "$NS" delete -f pod.yaml
}
trap cleanup EXIT
trap cleanup ERR

# read return non zero
read -r -d '' SCRIPT <<'EOF' || :
<%= @script %>
EOF

podname="${BUILD_TAG:-oncall-1}"
podname=$(echo "$podname" | sed -e 's/[^A-z0-9\d\-\.]//g' | sed -e 's/\(.*\)/\L\1/')
secret_names=$(kubectl -n "$NS" describe secret "$SECRET" | awk -F':' '/bytes/ {print $1}')

secret_kvs=""
for secret_key in $secret_names; do
  secret_kvs=$(cat <<-EOF
      - name: $(echo $secret_key | sed 's/\./_/g')
        valueFrom:
          secretKeyRef:
            key: "$secret_key"
            name: "$SECRET"
${secret_kvs}
EOF
)
done

cat <<-EOF > pod.yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: ${podname}
  namespace: ${NS}
spec:
  containers:
  - env:
${secret_kvs}
    image: ${IMAGE}
    command:
    - "sleep"
    - "7200"
    imagePullPolicy: Always
    name: runner
    resources: {}
    securityContext:
      privileged: false
  dnsPolicy: ClusterFirst
  imagePullSecrets:
  - name: docker-ops-admin
EOF

cat pod.yaml
kubectl -n "$NS" apply -f pod.yaml

# Waiting until the pod is ready
status=""
while [ ! "$status" = "Running" ]; do
  status=$(kubectl -n "$NS" get pod "$podname" -o jsonpath='{.status.phase}')
  echo -n .
  sleep 2
done

echo -e "\n\n --> Pod is ready. Run script\n"
kubectl -n "$NS" exec "$podname" -- /bin/bash -c "$SCRIPT"
rm pod.yaml
