#!/bin/bash
# Quick Deploy muBench Services with Enhanced Code

set -euo pipefail

NAMESPACE="default"
IMAGE="msvcbench/microservice:v3-enhanced"
COMM_PROTOCOL="${COMM_PROTOCOL:-http}"

echo "🚀 Desplegando servicios muBench con código enhanced..."
echo "Protocolo: $COMM_PROTOCOL"

# Delete old deployments if they exist
microk8s kubectl delete deployment s0 s1 sdb1 -n $NAMESPACE 2>/dev/null || true
microk8s kubectl delete svc s0 s1 sdb1 -n $NAMESPACE 2>/dev/null || true

# Wait for deletion
sleep 5

# Deploy s0
cat <<EOF | microk8s kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: s0
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: s0
  template:
    metadata:
      labels:
        app: s0
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
      - name: s0
        image: $IMAGE
        imagePullPolicy: Never
        ports:
        - containerPort: 8080
        env:
        - name: APP
          value: s0
        - name: ZONE
          value: default
        - name: K8S_APP
          value: s0
        - name: PN
          value: "1"
        - name: TN
          value: "4"
        - name: COMM_PROTOCOL
          value: "$COMM_PROTOCOL"
        - name: NAMESPACE
          value: $NAMESPACE
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 10
        volumeMounts:
        - name: microservice-workmodel
          mountPath: /app/MSConfig
      volumes:
      - name: microservice-workmodel
        configMap:
          name: workmodel
          optional: true
---
apiVersion: v1
kind: Service
metadata:
  name: s0
  namespace: $NAMESPACE
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "80"
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
    name: http
  selector:
    app: s0
EOF

# Deploy s1
cat <<EOF | microk8s kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: s1
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: s1
  template:
    metadata:
      labels:
        app: s1
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
      - name: s1
        image: $IMAGE
        imagePullPolicy: Never
        ports:
        - containerPort: 8080
        env:
        - name: APP
          value: s1
        - name: ZONE
          value: default
        - name: K8S_APP
          value: s1
        - name: PN
          value: "1"
        - name: TN
          value: "4"
        - name: COMM_PROTOCOL
          value: "$COMM_PROTOCOL"
        - name: NAMESPACE
          value: $NAMESPACE
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 10
        volumeMounts:
        - name: microservice-workmodel
          mountPath: /app/MSConfig
      volumes:
      - name: microservice-workmodel
        configMap:
          name: workmodel
          optional: true
---
apiVersion: v1
kind: Service
metadata:
  name: s1
  namespace: $NAMESPACE
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "80"
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
    name: http
  selector:
    app: s1
EOF

# Deploy sdb1
cat <<EOF | microk8s kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sdb1
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sdb1
  template:
    metadata:
      labels:
        app: sdb1
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
      - name: sdb1
        image: $IMAGE
        imagePullPolicy: Never
        ports:
        - containerPort: 8080
        env:
        - name: APP
          value: sdb1
        - name: ZONE
          value: default
        - name: K8S_APP
          value: sdb1
        - name: PN
          value: "1"
        - name: TN
          value: "4"
        - name: COMM_PROTOCOL
          value: "$COMM_PROTOCOL"
        - name: NAMESPACE
          value: $NAMESPACE
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 10
        volumeMounts:
        - name: microservice-workmodel
          mountPath: /app/MSConfig
      volumes:
      - name: microservice-workmodel
        configMap:
          name: workmodel
          optional: true
---
apiVersion: v1
kind: Service
metadata:
  name: sdb1
  namespace: $NAMESPACE
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "80"
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
    name: http
  selector:
    app: sdb1
EOF

echo "✅ Servicios desplegados"
echo "Esperando a que los pods estén listos..."
sleep 15

microk8s kubectl get pods -n $NAMESPACE | grep -E "s0|s1|sdb"
echo ""
echo "✅ Despliegue completado"
