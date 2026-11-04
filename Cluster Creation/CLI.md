Prerequisites:
- Install : aws cli, eksctl, kubectl
- Configure AWS-CLI via aws configure command
```
eksctl create cluster --name prod-upgrade-demo --region ap-south-1 --version 1.33 --nodegroup-name ng-1 --node-type t3a.xlarge --nodes 2 --managed
```
**You can change the node type as per your requirement like t3.medium or t2.medium**
