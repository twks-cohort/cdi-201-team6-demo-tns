#!/usr/bin/env bash
set -e

export ENVIRONMENT=$1
export NAMESPACE=tns-cloud-$ENVIRONMENT
export LOG_LEVEL=$(cat environments/${ENVIRONMENT}.json | jq -r .log_level)
export APP_REPLICAS=$(cat environments/${ENVIRONMENT}.json | jq -r .app_replicas)
export DB_REPLICAS=$(cat environments/${ENVIRONMENT}.json | jq -r .db_replicas)
export LOADGEN_REPLICAS=$(cat environments/${ENVIRONMENT}.json | jq -r .loadgen_replicas)
export CLUSTER=$(cat environments/${ENVIRONMENT}.json | jq -r .cluster)


cat <<EOF > tns-deploy/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    istio-injection: enabled
    name: $NAMESPACE
  name: $NAMESPACE
EOF

cat <<EOF > tns-deploy/deployments.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: $NAMESPACE
spec:
  minReadySeconds: 10
  replicas: $APP_REPLICAS
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      name: app
  template:
    metadata:
      labels:
        name: app
    spec:
      containers:
      - args:
        - -log.level=$LOG_LEVEL
        - http://db
        env:
        - name: JAEGER_AGENT_HOST
          value: grafana-agent-traces.grafana-system.svc.cluster.local
        - name: JAEGER_TAGS
          value: cluster=$CLUSTER,namespace=$NAMESPACE
        - name: JAEGER_SAMPLER_TYPE
          value: const
        - name: JAEGER_SAMPLER_PARAM
          value: "1"
        image: grafana/tns-app:latest
        imagePullPolicy: IfNotPresent
        name: app
        ports:
        - containerPort: 80
          name: http-metrics
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db
  namespace: $NAMESPACE
spec:
  minReadySeconds: 10
  replicas: $DB_REPLICAS
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      name: db
  template:
    metadata:
      labels:
        name: db
    spec:
      containers:
      - args:
        - -log.level=$LOG_LEVEL
        env:
        - name: JAEGER_AGENT_HOST
          value: grafana-agent-traces.grafana-system.svc.cluster.local
        - name: JAEGER_TAGS
          value: cluster=$CLUSTER,namespace=$NAMESPACE
        - name: JAEGER_SAMPLER_TYPE
          value: const
        - name: JAEGER_SAMPLER_PARAM
          value: "1"
        image: grafana/tns-db:latest
        imagePullPolicy: IfNotPresent
        name: db
        ports:
        - containerPort: 80
          name: http-metrics
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loadgen
  namespace: $NAMESPACE
spec:
  minReadySeconds: 10
  replicas: $LOADGEN_REPLICAS
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      name: loadgen
  template:
    metadata:
      labels:
        name: loadgen
    spec:
      containers:
      - args:
        - -log.level=$LOG_LEVEL
        - http://app
        env:
        - name: JAEGER_AGENT_HOST
          value: grafana-agent-traces.grafana-system.svc.cluster.local
        - name: JAEGER_TAGS
          value: cluster=$CLUSTER,namespace=$NAMESPACE
        - name: JAEGER_SAMPLER_TYPE
          value: const
        - name: JAEGER_SAMPLER_PARAM
          value: "1"
        image: grafana/tns-loadgen:latest
        imagePullPolicy: IfNotPresent
        name: loadgen
        ports:
        - containerPort: 80
          name: http-metrics
EOF

cat <<EOF > tns-deploy/services.yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    name: app
  name: app
  namespace: $NAMESPACE
spec:
  ports:
  - name: app-http-metrics
    port: 80
    targetPort: 80
  selector:
    name: app
---
apiVersion: v1
kind: Service
metadata:
  labels:
    name: db
  name: db
  namespace: $NAMESPACE
spec:
  ports:
  - name: db-http-metrics
    port: 80
    targetPort: 80
  selector:
    name: db
---
apiVersion: v1
kind: Service
metadata:
  labels:
    name: loadgen
  name: loadgen
  namespace: $NAMESPACE
spec:
  ports:
  - name: loadgen-http-metrics
    port: 80
    targetPort: 80
  selector:
    name: loadgen
EOF

cat <<EOF > tns-deploy/monitors.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: tns-cloud-app-monitor-$ENVIRONMENT
  labels:
    monitoring: tns-cloud-app-$ENVIRONMENT
    release: prometheus
spec:
  jobLabel: tns-cloud-app-$ENVIRONMENT
  targetLabels: [name]
  selector:
    matchLabels:
        name: app
  namespaceSelector:
    matchNames:
    - $NAMESPACE
  endpoints:
  - port: app-http-metrics
    interval: 15s
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: tns-cloud-db-monitor-$ENVIRONMENT
  labels:
    monitoring: tns-cloud-db-$ENVIRONMENT
    release: prometheus
spec:
  jobLabel: tns-cloud-db-$ENVIRONMENT
  targetLabels: [name]
  selector:
    matchLabels:
        name: db
  namespaceSelector:
    matchNames:
    - $NAMESPACE
  endpoints:
  - port: db-http-metrics
    interval: 15s
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: tns-cloud-loadgen-monitor-$ENVIRONMENT
  labels:
    monitoring: tns-cloud-loadgen-$ENVIRONMENT
    release: prometheus
spec:
  jobLabel: tns-cloud-loadgen-$ENVIRONMENT
  targetLabels: [name]
  selector:
    matchLabels:
        name: loadgen
  namespaceSelector:
    matchNames:
    - $NAMESPACE
  endpoints:
  - port: loadgen-http-metrics
    interval: 15s
EOF

cat <<EOF > tns-deploy/gateway.yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: tns-cloud-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
EOF

cat <<EOF > tns-deploy/virtual-service.yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: tns-cloud-app
  namespace: $NAMESPACE
spec:
  hosts:
  - "*"
  gateways:
  - istio-system/tns-cloud-gateway
  http:
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: "app.$NAMESPACE.svc.cluster.local"
EOF

cat <<EOF > tns-deploy/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

commonLabels:
  app: tns-cloud
  team: tns-engineering
  env: dev

resources:
  - namespace.yaml
  - deployments.yaml
  - services.yaml
  - monitors.yaml
  - gateway.yaml
  - virtual-service.yaml
EOF

kubectl apply -k tns-deploy
