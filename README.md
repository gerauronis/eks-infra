
### Instalación

**1. Si no hay cluster hay que crear el clúster EKS**

```bash
eksctl create cluster -f cluster/cluster-config-develop.yaml
```

Espera a que se complete la creación del clúster.

**2 Crear la policy**

```bash
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json
aws iam create-policy --policy-name AWSLBCIAMPolicyEksKometaDev --policy-document file://iam_policy.json
```

Te devuelve el ARN que hay que copiar:
arn:aws:iam::202533518394:policy/AWSLBCIAMPolicyEksKometaDev

Asociar la política:

```bash
eksctl utils associate-iam-oidc-provider --region us-east-1 --cluster kometa-dev --approve

eksctl create iamserviceaccount   --cluster kometa-dev   --namespace kube-system   --name aws-load-balancer-controller-dev   --attach-policy-arn arn:aws:iam::202533518394:policy/AWSLBCIAMPolicyEksKometaDev   --approve
```

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller-dev eks/aws-load-balancer-controller   --set clusterName=kometa-dev   --set serviceAccount.create=false   --set region=us-east-1   --set vpcId=vpc-0dc7d5b47d7a8fb15   --set serviceAccount.name=aws-load-balancer-controller-dev   --namespace kube-system
```

**3. Actualizar proyectos**

```bash
helm lint ./src -f src/values-develop.yaml
```

Crear namespace:

```bash
kubectl create namespace kometa-develop
```

Crear nodegroup:

```bash
eksctl create nodegroup -f cluster/cluster-config-develop.yaml             
```

Simulación:

```bash
helm install kometa-develop ./src --namespace kometa-develop --dry-run --debug -f src/values-develop.yaml
```

Deploy:

```bash
helm install kometa-develop ./src --namespace kometa-develop -f src/values-develop.yaml
```

After Update change context depend to stage:

```bash
kubectl config get-contexts

kubectl config use-context test@kometa-dev.us-east-2.eksctl.io
```

```bash
helm upgrade kometa-develop ./src --namespace kometa-develop -f src/values-develop.yaml
```

Desinstalar
```bash
helm uninstall kometa-develop --namespace kometa-develop
```

Eliminar el clúster:

```bash
eksctl delete cluster -f cluster/cluster-config-develop.yaml --disable-nodegroup-eviction
```

Check Ingress
```bash
kubectl describe ingress kometa-develop -n kometa-develop
```

Check cron
```bash
kubectl get cronjobs -n kometa-develop
kubectl describe cronjob scale-up-pods -n kometa-develop
```

Added new context
```bash
aws eks update-kubeconfig --region "us-east-1" --name "kometa-prod"
```

Review template
```bash
 helm template kometa-develop ./src \
  --namespace kometa-develop \
  -f src/values-develop.yaml > out.yaml
```
