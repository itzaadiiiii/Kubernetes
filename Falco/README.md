# Kubernetes Falco: Complete Beginner-to-Enterprise Tutorial
## From zero to production-grade runtime security for FinTech, banking, healthcare, and cloud-native applications

I'll walk you through **Falco from the fundamentals to production deployment**, including installation on Kubernetes, custom security rules, real attack-detection examples, alerting, incident response, and enterprise architecture.

We'll use an AWS EKS environment as our primary example, with Java Spring Boot microservices, Helm, Terraform, Argo CD, Prometheus, Grafana, and centralized logging. The same concepts apply to other Kubernetes platforms, including AKS and GKE.

By the end, you should be able to explain how Falco works in a real enterprise environment and demonstrate it practically in an interview.

---

# 1. What is Falco?

Falco is an open-source runtime security tool that detects suspicious activity on Linux hosts and inside containerized environments.

It observes system activity and evaluates it against security rules. When an activity matches a rule, Falco generates an event.

For example, imagine your FinTech application runs 45 Java microservices on EKS.

One microservice handles customer transactions. Its container normally:
- Runs a Java process.
- Reads application configuration.
- Retrieves secrets through an approved mechanism.
- Connects to MySQL or another approved database.
- Writes application logs to standard output.

Now suppose someone gains access to that container and executes:

```bash
kubectl exec -it payment-service-abc123 -- /bin/sh
```

They then run:

```bash
cat /etc/shadow
```

Or execute an unexpected shell inside the container:

```bash
bash -c "whoami"
```

These activities might be suspicious in a production payment-processing service.

**Falco can detect relevant runtime activity and generate security alerts according to your configured rules.**

However, detection depends on the rules you enable, the events Falco can observe, and the permissions and visibility of your deployment. Falco does not automatically identify every attack.

## 1.1 Why isn't Kubernetes RBAC enough?

Kubernetes RBAC controls which Kubernetes API operations a user or service account is authorized to perform.

For example:

| Security control | What it does |
|---|---|
| Kubernetes RBAC | Controls access to Kubernetes API resources |
| NetworkPolicy | Restricts network communication between selected workloads |
| Pod Security Admission | Enforces Kubernetes pod security standards |
| IAM and EKS access controls | Control AWS and Kubernetes access according to the configured identity and permissions |
| Image scanning | Detects known vulnerabilities in container images |
| Admission policies | Prevent certain workloads or configurations from being deployed |
| Falco | Detects suspicious runtime activity on the host and in workloads |

Consider a developer who has legitimate permission to access a development pod. If the developer's credentials are compromised, an attacker might use that access to execute commands inside the pod.

RBAC may permit the initial action because the credentials have the required permission. Falco can potentially detect the subsequent suspicious activity inside the container.

**The key distinction: RBAC helps control access; Falco helps detect suspicious behavior at runtime.**

These controls complement each other rather than replace one another.

---

# 2. How Falco works internally

Before installing Falco, understand its architecture.

```text
                  AWS EKS CLUSTER
┌─────────────────────────────────────────────────────┐
│                                                     │
│  Worker Node 1                 Worker Node 2        │
│  ┌─────────────────────┐      ┌─────────────────┐  │
│  │ Java Payment Pod    │      │ Java Loan Pod   │  │
│  │                     │      │                 │  │
│  │ Java Process        │      │ Java Process    │  │
│  └──────────┬──────────┘      └────────┬────────┘  │
│             │                          │           │
│             ▼                          ▼           │
│  ┌─────────────────────┐      ┌─────────────────┐  │
│  │ Linux Kernel Events │      │ Kernel Events   │  │
│  └──────────┬──────────┘      └────────┬────────┘  │
│             │                          │           │
│             ▼                          ▼           │
│  ┌─────────────────────┐      ┌─────────────────┐  │
│  │ Falco Agent         │      │ Falco Agent     │  │
│  │                     │      │                 │  │
│  │ Event Collection    │      │ Event Collection│  │
│  │ Rule Evaluation     │      │ Rule Evaluation │  │
│  └──────────┬──────────┘      └────────┬────────┘  │
│             │                          │           │
└─────────────┼──────────────────────────┼───────────┘
              │                          │
              └────────────┬─────────────┘
                           ▼
                  Security Event Output
                           │
             ┌─────────────┼──────────────┐
             ▼             ▼              ▼
         CloudWatch    SIEM/SOC       Alerting
                                  PagerDuty/Slack
```

This is a conceptual architecture. The precise deployment and event-routing configuration depends on your environment.

## 2.1 The major components

### A. Linux kernel event collection

Falco needs a way to observe system activity.

Depending on the supported configuration, it can use:
- A modern eBPF-based event-probe driver.
- A kernel module driver.
- Other supported event sources and plugins for applicable data sources.

The kernel event source allows Falco to observe relevant activity such as process execution, file access, and other system operations.

For an EKS environment, the chosen driver must be compatible with the worker-node operating system, kernel, and Falco version.

### B. Falco event processing

Falco receives events and evaluates them against its rules.

For example, a rule might detect a shell being executed inside a container.

The event can contain contextual fields such as:
- Process name.
- Executable path.
- User ID.
- Container ID.
- Kubernetes namespace.
- Pod name.
- Parent process.
- Event type.

The exact fields available depend on the event source and configuration.

### C. Falco rules engine

The rules engine evaluates conditions and determines whether an event matches a configured rule.

For example:

```text
IF a shell is executed
AND the process runs inside a container
AND the container belongs to a production namespace
THEN generate a security alert
```

This is illustrative pseudocode, not a complete Falco rule.

### D. Outputs and integrations

When Falco detects a matching event, it can send the event to configured outputs.

Examples include:
- Standard output and logs.
- A supported HTTP or other output integration.
- A Falco event forwarder.
- A SIEM or security analytics platform.
- A custom event-processing service.

Falco itself is primarily a detection engine. Your incident-response system determines what happens after detection.

---

# 3. Install Falco in a Kubernetes cluster

Let's move to the practical implementation.

You can deploy Falco on a local Linux Kubernetes cluster or a non-production EKS cluster. For a Windows laptop, use a Linux-based Kubernetes environment such as a Linux VM, a suitable Linux node pool, or an AWS EKS cluster. Docker Desktop alone is not the recommended environment for this kernel-level Kubernetes lab.

## 3.1 Prerequisites

You need:

| Component | Purpose |
|---|---|
| Kubernetes cluster | Runs the application and Falco |
| `kubectl` | Manages Kubernetes resources |
| Helm | Installs and configures Falco |
| Linux worker nodes | Provide the kernel events Falco monitors |
| Appropriate cluster permissions | Allow installation of the required resources |
| Network access | Downloads the chart and required artifacts |

First, verify your cluster:

```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A
helm version
```

Confirm that your nodes are Linux-based:

```bash
kubectl get nodes \
  -o custom-columns=NAME:.metadata.name,OS:.status.nodeInfo.operatingSystem,KERNEL:.status.nodeInfo.kernelVersion
```

For production EKS, verify driver compatibility with the node AMI, kernel, architecture, and Falco version before rolling out the agent.

## 3.2 Install Falco using Helm

The official Falco documentation supports Helm deployment. For this introductory lab, we'll use the Helm chart method. [Falco](https://falco.org/docs/getting-started/deployment/?utm_source=chatgpt.com)

### Step 1: Add the Falco Helm repository

```bash
helm repo add falcosecurity \
  https://falcosecurity.github.io/charts

helm repo update
```

### Step 2: Install Falco

```bash
helm install falco \
  falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set tty=true
```

This creates the Falco installation in the `falco` namespace.

The standard Kubernetes deployment uses a DaemonSet so that a Falco agent can run on each eligible worker node.

**Why a DaemonSet?**

Imagine you have six EKS worker nodes:

```text
EKS Cluster
│
├── Worker Node 1 → Falco Agent
├── Worker Node 2 → Falco Agent
├── Worker Node 3 → Falco Agent
├── Worker Node 4 → Falco Agent
├── Worker Node 5 → Falco Agent
└── Worker Node 6 → Falco Agent
```

Each agent observes activity on its own host. A single Falco pod does not automatically provide complete syscall visibility into every other node.

DaemonSet placement can be affected by node selectors, tolerations, affinity, and other scheduling constraints. In production, verify that all intended nodes are covered.

### Step 3: Verify the deployment

```bash
kubectl get pods -n falco -o wide
kubectl get daemonset -n falco
```

Wait for the pods to become ready:

```bash
kubectl wait pods \
  --for=condition=Ready \
  --all \
  -n falco \
  --timeout=180s
```

Check the logs:

```bash
kubectl logs \
  -n falco \
  -l app.kubernetes.io/name=falco \
  --all-containers=true \
  --tail=100
```

If the pods are not ready, inspect their events and logs:

```bash
kubectl describe pods -n falco
kubectl get events -n falco --sort-by=.lastTimestamp
```

Look for driver initialization failures, unsupported kernel configurations, permission problems, or image-pull failures.

### An important enterprise distinction

The current Falco documentation recommends the **Falco Operator** for declarative, Kubernetes-native management. Helm remains a supported alternative. [Falco](https://falco.org/docs/setup/operator/?utm_source=chatgpt.com)

For learning, Helm is straightforward.

For a larger enterprise deployment, you should evaluate the Operator alongside your organization's GitOps practices, supported Kubernetes versions, rule management, and upgrade process.

Official guides:
- [Falco Kubernetes installation guide](https://falco.org/docs/getting-started/deployment/?utm_source=chatgpt.com)
- [Falco Operator installation guide](https://falco.org/docs/setup/operator/?utm_source=chatgpt.com)

---

# 4. Your first Falco security detection

Now we'll create an application and deliberately trigger a security rule.

We will not attack a real application or access real credentials. The following experiment runs in a test namespace.

## 4.1 Deploy a test application

Create an NGINX deployment:

```bash
kubectl create namespace falco-lab

kubectl create deployment nginx \
  --image=nginx:stable \
  --namespace=falco-lab

kubectl rollout status deployment/nginx \
  --namespace=falco-lab
```

Check the pod:

```bash
kubectl get pods -n falco-lab -o wide
```

## 4.2 Trigger a suspicious file-access event

Execute a command inside the test container:

```bash
kubectl exec -n falco-lab \
  deployment/nginx -- \
  cat /etc/shadow
```

In this lab, the purpose is to trigger a file-access event, not to extract credentials. You do not need the command to succeed to learn from the exercise.

Falco's standard rules include detections for certain attempts to read sensitive files. The official quickstart uses this example to demonstrate event detection. [Falco](https://falco.org/docs/getting-started/falco-kubernetes-quickstart/?utm_source=chatgpt.com)

## 4.3 Check Falco's output

Run:

```bash
kubectl logs \
  -n falco \
  -l app.kubernetes.io/name=falco \
  -c falco \
  --since=5m
```

You can filter for warning-level output:

```bash
kubectl logs \
  -n falco \
  -l app.kubernetes.io/name=falco \
  -c falco \
  --since=5m | grep -i warning
```

A matching event can include information resembling:

```text
Warning Sensitive file opened for reading by non-trusted program

file=/etc/shadow
process=cat
user=root
container_name=nginx
k8s_ns=falco-lab
k8s_pod_name=nginx-xxxxxxxxxx-xxxxx
```

The exact message and fields vary by version, rule configuration, and event context.

### What happened behind the scenes?

1. Kubernetes allowed the command to execute inside the test container.
2. The container process attempted to access a file.
3. The Linux event source exposed the relevant activity to Falco.
4. Falco evaluated the event against its loaded rules.
5. A matching rule generated an alert.
6. The event appeared in Falco's configured output.

**Notice that Falco detected the behavior after the container was running.** It did not need to rebuild the image or restart the application to observe the event.

This is the fundamental idea behind runtime security.

---

# 5. Understand Falco rules

This is the most important part of learning Falco.

A Falco rule defines:
- **Rule:** The detection's name.
- **Description:** What the detection identifies.
- **Condition:** Which events should match.
- **Output:** What information to include in the alert.
- **Priority:** How important the event is.
- **Tags:** Useful classification metadata.

A simplified example:

```yaml
- rule: Example Suspicious Shell
  desc: Detect a shell executed inside a container
  condition: >
    evt.type in (execve, execveat)
    and container.id != host
    and proc.name in (bash, sh, dash)
  output: >
    Shell executed in a container
    (user=%user.name
    process=%proc.name
    command=%proc.cmdline
    namespace=%k8s.ns.name
    pod=%k8s.pod.name)
  priority: WARNING
  tags: [container, process, runtime_security]
```

This is an illustrative custom rule. Before deploying it, validate the field names and event behavior against your installed Falco version and enabled event sources.

The logic is:

| Condition | Meaning |
|---|---|
| `evt.type in (execve, execveat)` | Evaluate process-execution events |
| `container.id != host` | Restrict the match to a container rather than a host process |
| `proc.name in (bash, sh, dash)` | Match selected shell process names |
| `priority: WARNING` | Classify the event as a warning |
| `tags` | Categorize the detection |

### Does every shell execution mean an attack?

No.

Developers and operators sometimes use shells for legitimate debugging, diagnostics, or maintenance.

Therefore, this rule is a starting point, not a complete production policy. It can produce false positives, and a production implementation should consider workload identity, namespace, process ancestry, approved maintenance workflows, and the expected behavior of each service.

For example, a shell inside a payment-processing container may deserve more scrutiny than a shell inside a dedicated troubleshooting container.

**Enterprise rule design is about identifying unexpected behavior in context, not simply banning every behavior that can be abused.**

---

# 6. Add custom Falco rules to Kubernetes

In a real company, you should not manually edit rules inside a running Falco container.

Instead, maintain custom rules in a Git repository and deploy them through Helm, the Falco Operator, or another supported configuration-management workflow.

This makes rule changes reviewable, version-controlled, and auditable.

## 6.1 Create a custom rules file

Create `falco-custom-rules.yaml`:

```yaml
- rule: Detect Shell in Application Container
  desc: Detect shell execution inside a container
  condition: >
    spawned_process
    and container
    and proc.name in (bash, sh, dash)
  output: >
    Shell execution detected
    (user=%user.name
    process=%proc.name
    command=%proc.cmdline
    parent=%proc.pname
    container=%container.name
    image=%container.image.repository
    namespace=%k8s.ns.name
    pod=%k8s.pod.name)
  priority: NOTICE
  tags: [container, process, runtime_security]
```

This example uses `spawned_process` and `container` macros from the standard Falco ruleset. Ensure those macros are available in your installed ruleset before deploying the rule. [Falco](https://falco.org/docs/concepts/rules/custom-ruleset/?utm_source=chatgpt.com)

The purpose is to detect selected shells launched inside containers.

It is deliberately broad for learning. In a production environment, you would refine it to avoid excessive alerts from approved operational activity.

## 6.2 Load the custom rule using Helm

The official chart supports custom rules through its `customRules` configuration.

Create `falco-values.yaml`:

```yaml
tty: true

customRules:
  falco-custom-rules.yaml: |-
    - rule: Detect Shell in Application Container
      desc: Detect shell execution inside a container
      condition: >
        spawned_process
        and container
        and proc.name in (bash, sh, dash)
      output: >
        Shell execution detected
        (user=%user.name
        process=%proc.name
        command=%proc.cmdline
        parent=%proc.pname
        container=%container.name
        image=%container.image.repository
        namespace=%k8s.ns.name
        pod=%k8s.pod.name)
      priority: NOTICE
      tags: [container, process, runtime_security]
```

Apply the configuration:

```bash
helm upgrade falco \
  falcosecurity/falco \
  --namespace falco \
  -f falco-values.yaml
```

**Important:** For an existing enterprise installation, use the same pinned chart version as the current release. Review the existing values before upgrading so you don't accidentally overwrite other configuration.

Check the rollout:

```bash
kubectl rollout status daemonset/falco \
  -n falco
```

If the chart uses a different DaemonSet name, retrieve the actual name first:

```bash
kubectl get daemonsets -n falco
```

Then inspect Falco's logs for rule-loading errors:

```bash
kubectl logs -n falco \
  -l app.kubernetes.io/name=falco \
  -c falco \
  --since=5m
```

## 6.3 Test your custom rule

Execute a shell inside the test application:

```bash
kubectl exec -n falco-lab \
  deployment/nginx -- \
  /bin/sh -c 'echo "Falco lab test"'
```

Look for your custom alert:

```bash
kubectl logs -n falco \
  -l app.kubernetes.io/name=falco \
  -c falco \
  --since=5m | grep -i "Shell execution detected"
```

The alert should appear if the rule is loaded correctly, the relevant event is observed, and the condition matches.

If you don't see it, check the loaded rule configuration, macros, available fields, event source, and which worker node hosts the test pod.

### How this works in a production CI/CD pipeline

A typical rule-management workflow is:

```text
Developer creates or updates a Falco rule
                    |
                    v
          Pull Request to Git
                    |
                    v
       YAML / Rule Validation
                    |
                    v
       Security Team Code Review
                    |
                    v
        Merge to Approved Branch
                    |
                    v
       Argo CD / Helm Deployment
                    |
                    v
       Falco agents load new rules
                    |
                    v
       Controlled detection tests
                    |
                    v
          Production rollout
```

This separation is important because a poorly designed rule can generate thousands of alerts or miss the behavior it was supposed to detect.

For the official syntax, exception handling, and rule customization guidance, see the [Falco custom rules documentation](https://falco.org/docs/concepts/rules/custom-ruleset/).

---

# 7. Six practical Falco detection scenarios

Now let's look at how Falco is used beyond basic shell detection.

These are examples of detection policies you might implement in an enterprise. They are not all complete, drop-in rules: some require adaptation to your workloads, and some behaviors are better detected through Kubernetes audit events or other security data sources.

## Scenario 1: Someone executes a shell inside a payment service

**Environment:** FinTech payment-processing microservice.

**Normal behavior:** A Java process handles HTTP requests and processes transactions.

**Suspicious behavior:** An unexpected shell starts inside the application container.

Example:

```text
Namespace: prod-payments
Pod: payment-service-7f4c9d
Process: /bin/sh
Parent process: java
Severity: Notice or Warning, depending on policy
```

### How Falco helps

1. Observes the relevant process-execution event.
2. Evaluates the event against the custom rule.
3. Adds available process and Kubernetes metadata.
4. Generates an event.
5. Sends the event to your security monitoring pipeline.

### What happens next?

Your SOC or incident-response automation correlates the alert with Kubernetes audit logs, deployment history, identity information, and other telemetry.

If the activity is confirmed to be unauthorized, the response might include:
- Restricting the actor's access.
- Investigating the pod and its associated workload.
- Preserving relevant logs.
- Replacing a potentially compromised workload.
- Rotating affected credentials where warranted.

Falco detects suspicious activity; it does not independently prove that the developer or pod is compromised.

---

## Scenario 2: A process accesses a sensitive file

**Environment:** A wealth-management application handling customer information.

Imagine an application container unexpectedly attempts to read a sensitive system file.

Example:

```text
Rule: Sensitive file access
Namespace: prod-wealth
Pod: customer-profile-service-xxxx
Process: cat
Target: /etc/shadow
```

### How it is used

Falco's standard rules include sensitive-file-access detections.

The security team can investigate:
- Which process attempted the access?
- Which container image was running?
- What user executed the process?
- Was the action part of an approved diagnostic procedure?
- Was there additional suspicious activity?

A critical distinction: accessing a file in a container is not automatically equivalent to accessing the corresponding file on the host. The event's actual path, mount configuration, container boundaries, and permissions matter.

**Enterprise lesson:** Monitor sensitive file access, but don't assume every match represents a successful data breach.

---

## Scenario 3: Someone modifies system configuration inside a container

**Environment:** Banking API running in Kubernetes.

A production application should not ordinarily modify system configuration files inside its container.

Suppose a process attempts to write to `/etc`.

An example detection can be built around file-open events and write access, as shown in the official Falco quickstart. [Falco](https://falco.org/docs/getting-started/falco-kubernetes-quickstart/?utm_source=chatgpt.com)

Example event:

```text
Rule: Unexpected system configuration modification
Namespace: prod-banking
Pod: account-service-xxxx
Process: touch
Target: /etc/example.conf
```

### How it helps

This may identify:
- Unexpected changes to system configuration.
- Suspicious post-exploitation behavior.
- Application processes operating beyond their expected role.
- Attempts to establish persistence within a writable container filesystem.

### Important limitation

A write attempt is not necessarily a successful modification. A read-only filesystem, Unix permissions, or other controls may prevent the operation.

Falco can help detect the activity, while other controls prevent or restrict it.

For stronger protection, combine Falco with:

- Read-only root filesystems.
- Non-root containers.
- Dropped Linux capabilities.
- Restricted pod security settings.
- Immutable, verified container images.
- Kubernetes admission policies.

---

## Scenario 4: An unexpected executable runs inside a container

**Environment:** Healthcare application processing reimbursement requests.

Suppose a Java application normally executes only the expected Java runtime and application processes, but an unexpected utility appears.

Example:

```text
Expected process: java
Unexpected process: nc
Namespace: prod-healthcare
Pod: reimbursement-api-xxxx
```

This is an illustrative example, not a complete detection rule.

### Why this matters

Unexpected processes may indicate:
- A compromised application.
- An unauthorized debugging session.
- An unexpected dependency or script.
- An attempt to establish an unauthorized network connection.

However, executable names alone are weak indicators. Legitimate applications may invoke shell utilities, and an attacker can rename an executable.

A better policy evaluates the executable alongside the parent process, image, workload, namespace, and other available context.

For example, an unexpected process launched by a Java application in a payment pod may be more concerning than the same process launched by an approved troubleshooting workload.

---

## Scenario 5: A privileged container appears

**Environment:** Enterprise Kubernetes platform.

A privileged container can have significantly more access to the underlying host than an ordinary restricted container.

Falco's standard rules include detections related to privileged container activity.

Example:

```text
Event: Privileged container started
Namespace: prod-payments
Workload: payment-service
Severity: High according to local policy
```

### How to prevent the issue

Use admission controls to prevent unauthorized privileged workloads from being deployed.

For example, evaluate Kubernetes Pod Security Standards, admission policies, and organization-specific rules.

Falco can then provide a runtime detection layer for relevant activity.

**Do not rely on Falco as the primary mechanism for preventing privileged pods.** Admission control is the more appropriate enforcement point for rejecting an impermissible pod specification before deployment.

---

## Scenario 6: Suspicious activity across several microservices

**Environment:** A FinTech platform running dozens of microservices.

Imagine the following sequence:

```text
10:00:01 — Unexpected shell in payment-service
10:00:03 — Sensitive file access in payment-service
10:00:06 — Unexpected process in customer-service
10:00:09 — Unusual network activity in another workload
```

One event might be benign. Multiple correlated events can indicate a broader incident.

### How the enterprise SOC responds

A security analytics platform can correlate Falco alerts with:
- Kubernetes audit events.
- AWS CloudTrail events.
- IAM identity information.
- VPC Flow Logs.
- Application logs.
- Container image and deployment metadata.
- Endpoint or cloud workload security telemetry.

A response policy might assign a higher incident severity when multiple high-confidence detections occur within a short period.

Falco does not automatically know that these four events belong to the same attack. Correlation generally happens downstream in the SIEM or security analytics layer.

---

# 8. How to use Falco in an enterprise FinTech application

Let's design a realistic production architecture for a wealth-management or banking platform running on AWS EKS.

Assume the platform has:
- 45+ Java Spring Boot microservices.
- Amazon EKS for container orchestration.
- Amazon RDS for MySQL.
- AWS Secrets Manager for application secrets.
- AWS Load Balancer Controller for application ingress.
- Argo CD for GitOps deployments.
- Prometheus and Grafana for monitoring.
- Loki and Tempo for logs and traces.
- CloudTrail and CloudWatch for AWS auditing and logging.

## 8.1 Production architecture

```text
                        USERS
                          |
                          v
                  Amazon CloudFront
                          |
                          v
                    AWS WAF / ALB
                          |
                          v
                   AWS EKS CLUSTER
        ┌───────────────────────────────────┐
        │                                   │
        │  prod-payments namespace          │
        │  ┌─────────────────────────────┐  │
        │  │ Payment Service             │  │
        │  │ Java Spring Boot            │  │
        │  └─────────────────────────────┘  │
        │                                   │
        │  prod-accounts namespace          │
        │  ┌─────────────────────────────┐  │
        │  │ Account Service             │  │
        │  └─────────────────────────────┘  │
        │                                   │
        │  prod-customer namespace          │
        │  ┌─────────────────────────────┐  │
        │  │ Customer Service            │  │
        │  └─────────────────────────────┘  │
        │                                   │
        │  Falco DaemonSet                  │
        │  ├── Agent on worker node 1       │
        │  ├── Agent on worker node 2       │
        │  ├── Agent on worker node 3       │
        │  └── Agent on worker node N       │
        │                                   │
        └─────────────────┬─────────────────┘
                          |
                          v
                 Falcosidekick
                          |
             ┌────────────┼──────────────┐
             |            |              |
             v            v              v
          SIEM/SOC     CloudWatch    Incident Platform
             |                           |
             v                           v
       Security Team               PagerDuty/Slack
```

This architecture separates detection from incident management.

Falco observes runtime activity. Falcosidekick can forward events to supported destinations. The security operations platform correlates those events and determines which incidents require investigation.

For a centralized security architecture spanning multiple AWS accounts, forward events to a controlled, centrally managed destination rather than relying exclusively on logs retained inside individual clusters.

## 8.2 Where does Falco run?

For standard Linux kernel event monitoring, Falco is generally deployed as a DaemonSet.

If your EKS cluster has six eligible worker nodes, you would typically expect six Falco agents, subject to scheduling and deployment configuration.

If your cluster autoscaler adds four nodes, the DaemonSet should schedule additional agents on those nodes when they meet its scheduling requirements.

This matters because new worker nodes must also receive runtime security coverage.

**Production requirement:** Track the number of eligible nodes against the number of ready Falco agents. A cluster can be healthy from an application perspective while a runtime security agent is missing or failing.

## 8.3 What about Fargate?

Amazon EKS on Fargate has a different node and kernel-access model from conventional EC2-backed EKS nodes.

Do not assume that a Falco DaemonSet deployed on EC2 worker nodes will also provide equivalent syscall visibility into Fargate workloads.

For workloads running on Fargate, evaluate which runtime security capabilities are supported by your chosen security product and AWS's available telemetry. You may need a different detection approach.

---

# 9. Falco versus Prometheus, Grafana, Loki and Tempo

This is a common DevOps and SRE interview question.

These tools solve different problems.

| Tool | Primary responsibility | Example |
|---|---|---|
| Falco | Runtime security detection | Detect unexpected shell execution |
| Prometheus | Metrics collection and monitoring | Track CPU, memory, and request error rates |
| Grafana | Dashboards and visualization | Display application and infrastructure health |
| Loki | Log storage and querying | Search application and infrastructure logs |
| Tempo | Distributed trace storage | Follow a request across multiple microservices |
| OpenTelemetry | Instrumentation and telemetry collection | Collect application traces, metrics, and logs |
| CloudTrail | AWS API activity auditing | Investigate who changed an AWS resource |
| CloudWatch | AWS metrics, logs, and alarms | Monitor EKS-related telemetry and application logs |
| SIEM | Security-event correlation and investigation | Correlate Falco alerts with AWS audit events |

### Example: A payment service incident

Suppose a payment API suddenly experiences elevated errors.

Prometheus might show:

```text
HTTP 5xx errors: Increased
Request latency: Increased
CPU utilization: 85%
```

Tempo may reveal that requests are spending too long in a downstream service.

Loki may contain the relevant application errors.

Meanwhile, Falco may detect an unexpected shell launched inside the payment container.

These observations answer different questions:

- **Prometheus:** Is the service unhealthy?
- **Tempo:** Where is the request spending time?
- **Loki:** What did the application log?
- **Falco:** Is there suspicious runtime behavior?
- **SIEM:** Do the security events and other evidence indicate an incident?

A security alert can help explain an operational incident, but a Falco alert alone does not prove the cause of an outage.

---

# 10. Forward Falco alerts to a central security platform

Falco can write alerts to standard output, files, syslog, and HTTP/HTTPS endpoints. Its ecosystem also supports event forwarding through Falcosidekick. See the official [Falco outputs documentation](https://falco.org/docs/concepts/outputs/). [Falco](https://falco.org/docs/concepts/outputs/?utm_source=chatgpt.com)

For an enterprise deployment, avoid relying on someone manually running `kubectl logs` to discover security incidents.

Instead, design a durable alert pipeline.

## 10.1 Example event flow

```text
Falco Agent
    |
    v
Structured Security Event
    |
    v
Falcosidekick
    |
    v
Central Security Ingestion
    |
    v
SIEM / Security Analytics
    |
    v
Correlation and Severity Assessment
    |
    v
PagerDuty / Incident Management
```

The actual implementation depends on the supported integration and your organization's security platform.

## 10.2 Enable structured JSON output

JSON makes it easier for downstream systems to parse security events.

An example Falco configuration fragment is:

```yaml
json_output: true
json_include_output_property: true
```

The exact configuration options should be checked against your installed Falco version and existing Helm values.

With structured output, an event might resemble:

```json
{
  "rule": "Detect Shell in Application Container",
  "priority": "Notice",
  "output": "Shell execution detected",
  "output_fields": {
    "proc.name": "sh",
    "k8s.ns.name": "prod-payments",
    "k8s.pod.name": "payment-service-xxxx"
  }
}
```

This is an illustrative event, not a guaranteed output schema. Actual fields depend on the rule, event source, and Falco configuration.

### Why is JSON useful?

A downstream processor can extract the namespace, pod, process, and rule name without having to parse a free-form message.

That enables:
- Filtering by production namespace.
- Deduplicating repeated alerts.
- Routing critical events to the security team.
- Correlating events with deployment metadata.
- Measuring detection and response times.

## 10.3 Example severity-based routing

A possible enterprise policy:

| Detection | Destination | Action |
|---|---|---|
| Unexpected shell in production | Security queue | Investigate |
| Sensitive file access | Security queue | Correlate with other events |
| Confirmed critical runtime threat | On-call security team | Page according to incident policy |
| Expected troubleshooting activity | Security audit logs | Retain according to policy |
| Repeated correlated detections | SIEM incident | Investigate as a potential incident |

The exact severity should depend on the detection's confidence, workload sensitivity, and business impact.

**Important:** A Falco rule's priority is not automatically equivalent to your SIEM's incident severity. Define an explicit mapping in your event-processing layer.

---

# 11. How to use Falco with AWS security services

In a FinTech environment, Falco should be one component of a broader security strategy.

## 11.1 Falco and CloudTrail

Consider this sequence:

1. An AWS identity makes a change to an EKS-related IAM role.
2. CloudTrail records the applicable AWS API activity.
3. A user or workload subsequently performs unexpected operations inside a container.
4. Falco detects a matching runtime event.
5. The security team correlates both events.

CloudTrail provides AWS API audit information. Falco provides runtime observations. Neither source alone necessarily explains the entire incident.

## 11.2 Falco and AWS Secrets Manager

Suppose your payment service retrieves database credentials through an approved identity and Secrets Manager integration.

Falco can detect certain suspicious runtime activities around processes and file access. However, it does **not automatically tell you that a secret was retrieved from Secrets Manager or that a particular secret was exposed**.

For that, use appropriate AWS audit events, IAM controls, application instrumentation, and secrets-access monitoring.

A robust setup includes:

- Least-privilege IAM roles for service accounts or EKS Pod Identity.
- Narrowly scoped secret access.
- Secret rotation.
- No secrets in container images or Git repositories.
- Auditing of relevant AWS API calls.
- Runtime monitoring for suspicious process and file activity.

## 11.3 Falco and Kubernetes audit logs

Falco's Linux syscall monitoring and Kubernetes audit-event monitoring are complementary.

| Activity | Useful telemetry |
|---|---|
| User creates a pod | Kubernetes audit logs |
| User executes a command through the Kubernetes API | Kubernetes audit logs, plus runtime events where observable |
| Process executes inside a container | Falco syscall monitoring |
| Container attempts sensitive file access | Falco syscall monitoring |
| IAM role or security group changes | CloudTrail |
| Application returns HTTP 500 errors | Application logs and Prometheus |
| Unauthorized network connection | Falco where supported, network telemetry, and other security controls |

The Kubernetes audit log records API-server activity. It does not replace runtime visibility into processes executing inside containers.

For Kubernetes API events, the Falco ecosystem provides a Kubernetes audit-event plugin. When using the Operator, the plugin can be managed through its plugin resources. Consult the [Falco Operator documentation](https://falco.org/docs/setup/operator/) for the applicable configuration. [Falco](https://falco.org/docs/setup/operator/?utm_source=chatgpt.com)

---

# 12. Advanced enterprise scenario: Detecting suspicious activity in payment microservices

Let's combine the concepts into a more realistic detection strategy.

Assume your environment has these workloads:

```text
prod-payments
    ├── payment-api
    ├── transaction-service
    └── settlement-service

prod-accounts
    ├── account-api
    └── customer-profile-service

prod-risk
    ├── fraud-detection-service
    └── risk-engine
```

Each service has a defined operational profile.

For example:

| Workload | Expected behavior | Activity worth investigating |
|---|---|---|
| Payment API | Java process handles requests | Unexpected interactive shell |
| Transaction service | Processes transactions and connects to approved dependencies | Unexpected executable or sensitive-file access |
| Settlement service | Processes settlement jobs | Unexpected modifications to system files |
| Customer profile | Reads and updates authorized customer data | Suspicious processes or unusual access patterns |
| Fraud detection | Runs scoring and analysis workloads | Unexpected changes to executables or configuration |

These are detection hypotheses. They must be validated against the actual applications before being treated as production rules.

## 12.1 Build rules around workload context

Instead of a global rule that treats every shell as equally suspicious, consider separate policies for:

- Production payment workloads.
- Production data-processing workloads.
- Development environments.
- Approved troubleshooting workloads.

The rule condition should identify the intended scope, using available event fields and carefully defined macros or exceptions.

A conceptual rule for a payment workload is:

```text
Detect a selected shell process
AND the event belongs to a container
AND the namespace is prod-payments
AND the process is not part of an approved workflow
```

This is policy pseudocode, not a drop-in Falco rule.

You should validate the namespace and process fields available in your version before translating the policy into Falco syntax.

### Why not whitelist everything?

Suppose you exclude every event generated by a particular image.

An attacker who compromises that workload might then perform suspicious actions without generating the alert you expected.

A better exception is as narrow as possible. The Falco documentation recommends considering the actor, action, and target rather than excluding an entire class of events based on a single attribute. [Falco](https://falco.org/docs/concepts/rules/exceptions/?utm_source=chatgpt.com)

---

# 13. Production-grade Falco deployment strategy

A working Falco installation is not automatically an enterprise-grade security solution.

Production readiness requires controlled deployment, operational monitoring, tested rules, and a reliable response process.

## 13.1 Deploy through GitOps

For a GitOps-managed EKS environment, maintain your Falco configuration in Git.

For example:

```text
platform-security/
├── falco/
│   ├── Chart.yaml
│   ├── values-dev.yaml
│   ├── values-qa.yaml
│   ├── values-prod.yaml
│   └── rules/
│       ├── process-rules.yaml
│       ├── filesystem-rules.yaml
│       └── application-rules.yaml
```

The exact layout is a design choice; the important part is separating environment-specific configuration from reusable detection rules.

A typical promotion process:

```text
Rule Change
    |
    v
Pull Request
    |
    v
Rule Validation and Testing
    |
    v
Security Approval
    |
    v
Development Cluster
    |
    v
QA / Staging
    |
    v
Production Rollout
    |
    v
Alert Verification and Monitoring
```

Pin your chart and image versions. Review release notes before upgrades and test driver compatibility with your EKS node images.

## 13.2 Use staged rollout

Do not deploy an entirely new ruleset to every production cluster without testing it.

A sensible rollout is:

1. Validate the rule syntax.
2. Test the rule against controlled events.
3. Deploy to a development cluster.
4. Measure alert volume and false positives.
5. Test in staging with representative workloads.
6. Obtain security approval.
7. Roll out to production in controlled stages.
8. Monitor event delivery and agent health.

For rules that are prone to false positives, start with a suitable low-severity or observation-oriented policy, then increase enforcement of the detection workflow as confidence improves.

Remember that Falco is a detection system: lowering a rule's priority does not necessarily make the underlying activity safe.

## 13.3 Monitor Falco itself

Your monitoring should include:

- Ready Falco agents versus eligible worker nodes.
- Agent restarts and initialization failures.
- Driver compatibility failures.
- Event-processing errors.
- Event delivery failures.
- Alert ingestion latency.
- Dropped events or buffer pressure, where exposed by the selected configuration.
- Rule-loading failures after upgrades.
- CPU and memory usage.

You should also verify that your SIEM continues receiving events when a node is replaced or a new node group is introduced.

An agent that is running but unable to observe kernel events is not providing the coverage you expect.

## 13.4 Protect the security agent

Falco's host-level visibility requires access that ordinary application containers should not receive.

The standard syscall-monitoring deployment may require privileged access or specific Linux capabilities, depending on the driver and configuration. [Falco](https://falco.org/docs/getting-started/deployment/?utm_source=chatgpt.com)

Therefore:

- Use the least privileges supported by your chosen driver and deployment.
- Restrict access to the Falco namespace.
- Protect the Helm values, rule repository, and deployment permissions.
- Avoid exposing Falco's management interfaces publicly.
- Use approved, pinned images and controlled upgrades.
- Protect credentials used by event-forwarding integrations.
- Monitor for attempts to disable or tamper with security agents.

Do not blindly remove capabilities or enable restrictive settings without testing them against the selected driver. The objective is least privilege without silently losing detection coverage.

---

# 14. Falco versus other runtime security tools

Falco is not the only option for runtime protection.

The best choice depends on whether you need an open-source detection engine, managed threat detection, commercial support, or a broader cloud security platform.

| Tool | Main focus | When it may fit |
|---|---|---|
| Falco | Rule-based runtime detection | Custom detections and flexible integration |
| AWS GuardDuty | Managed AWS threat detection | AWS account and supported workload threat detection |
| Sysdig Secure | Runtime threat detection and cloud-native security | Organizations seeking an integrated commercial platform |
| Aqua Security | Cloud-native workload security | Organizations seeking broader workload protection |
| Microsoft Defender for Cloud | Cloud security posture and workload protection | Organizations with Microsoft cloud security requirements |

These products have overlapping but different capabilities, licensing models, and deployment requirements. They are not interchangeable in every environment.

For an open-source EKS implementation, Falco can provide a flexible runtime detection layer. In a regulated financial organization, evaluate whether that layer meets your coverage, operational, compliance, and support requirements.

---

# 15. Troubleshooting Falco

Here are common problems you'll encounter when implementing Falco.

| Problem | Possible cause | What to check |
|---|---|---|
| Falco pod is `CrashLoopBackOff` | Driver initialization or configuration failure | Pod logs and events |
| Falco pod is `Pending` | Scheduling constraints or insufficient resources | Node selectors, taints, tolerations, capacity |
| No alert appears | Rule isn't loaded or event doesn't match | Rules, event source, macros, fields |
| Falco works on some nodes only | Driver or kernel incompatibility | Node OS, kernel version, agent placement |
| Too many alerts | Conditions are too broad | Rule scope, exceptions, application behavior |
| Alerts reach Falco but not the SIEM | Forwarding or ingestion failure | Falcosidekick logs, destination connectivity, credentials |
| Alerts stop after a node upgrade | Driver or kernel compatibility changed | Driver initialization and node image |
| Security coverage misses new nodes | DaemonSet scheduling or readiness issue | Eligible nodes versus ready agents |

### Useful diagnostic commands

Check the DaemonSet:

```bash
kubectl get daemonset -n falco
```

Check agent placement:

```bash
kubectl get pods -n falco -o wide
```

Inspect a particular pod:

```bash
kubectl describe pod \
  -n falco <falco-pod-name>
```

Check its logs:

```bash
kubectl logs \
  -n falco <falco-pod-name> \
  -c falco \
  --tail=200
```

Check recent events:

```bash
kubectl get events \
  -n falco \
  --sort-by=.lastTimestamp
```

To investigate missing alerts, first verify that the agent is observing events, then verify that the rule is loaded, and finally confirm that the event satisfies the rule's condition.

---

# 16. Hands-on lab checklist

Use this checklist to progress from beginner to production-ready understanding.

| Lab | Task | Expected outcome |
|---|---|---|
| 1 | Install Falco using Helm | Falco agents start on eligible nodes |
| 2 | Deploy NGINX | Test workload runs |
| 3 | Trigger sensitive-file access | Relevant built-in rule generates an alert |
| 4 | Create a custom shell-detection rule | Custom rule is loaded |
| 5 | Execute a shell in the test container | Custom detection can be verified |
| 6 | Add JSON output | Events can be processed as structured data |
| 7 | Configure an event forwarder | Alerts reach a test destination |
| 8 | Test rule exceptions | Approved activity can be handled appropriately |
| 9 | Test node replacement | Runtime coverage is restored on new nodes |
| 10 | Deploy through GitOps | Rules and configuration are version-controlled |
| 11 | Simulate an agent failure | Monitoring detects the coverage gap |
| 12 | Test the incident workflow | Security events reach the right team |

## Clean up the lab

When you're finished, remove the test workload:

```bash
kubectl delete namespace falco-lab
```

If Falco was installed exclusively for this lab and you no longer need it, remove it:

```bash
helm uninstall falco -n falco
kubectl delete namespace falco
```

**Do not run the uninstall commands against a shared or production cluster.** Remove only resources you created and have permission to delete.

---

# 17. Interview questions and answers

Here are the questions I'd prepare for a Cloud DevOps/SRE or platform-security interview.

### Q1. What is Falco, and why do we use it?

**Answer:**

Falco is an open-source runtime security tool that detects suspicious behavior on Linux hosts and in containerized environments. It evaluates system events against configurable rules and generates alerts when matching behavior is detected.

In Kubernetes, we can use it to detect suspicious process execution, sensitive file access, and other runtime activity. It complements RBAC, admission controls, image scanning, and network security.

### Q2. Why do we deploy Falco as a DaemonSet?

A DaemonSet allows us to run a Falco agent on each eligible worker node. Each agent monitors the system activity available from its host.

This gives us node-level runtime visibility across the cluster. We must also verify that newly added nodes receive an agent and that every agent is healthy.

### Q3. What is the difference between Falco and Trivy?

Trivy is commonly used to scan container images, filesystems, repositories, and other supported targets for vulnerabilities and misconfigurations.

Falco focuses on detecting suspicious activity at runtime.

For example, Trivy may identify a vulnerable package in an image before deployment. Falco may detect an unexpected shell executing inside a running container.

They are complementary security controls.

### Q4. Does Falco prevent attacks?

Falco is primarily a detection engine. It generates events when configured rules match observed activity.

You can connect those events to an automated response system, but the response mechanism is separate. Any automatic containment action must be carefully designed to avoid disrupting legitimate workloads.

### Q5. How do you integrate Falco into an enterprise CI/CD pipeline?

I would maintain custom Falco rules and deployment configuration in Git. Rule changes would go through pull requests, validation, security review, and staged deployment.

We would test detections in development and staging before promoting them to production. Argo CD or a controlled Helm deployment would manage the approved configuration.

### Q6. How would you use Falco in a FinTech application?

I would deploy Falco on eligible Linux-backed EKS worker nodes and use appropriate rules to monitor suspicious runtime behavior in sensitive workloads, such as payment and customer-data services.

I would forward structured alerts to a central security platform, correlate them with Kubernetes audit logs and AWS CloudTrail, and route confirmed high-priority incidents to the security operations team.

I would also monitor agent health and event-delivery reliability, review false positives, and manage rule changes through GitOps.

### Q7. What are the main challenges with Falco?

The main challenges include:
- Driver and kernel compatibility.
- False positives from legitimate application behavior.
- Missing runtime coverage on some nodes.
- Event volume and alert fatigue.
- Reliable delivery of security events.
- Safe management of rules and exceptions.
- Protecting an agent that needs host-level visibility.

We address these through compatibility testing, least-privilege configuration, workload-aware rules, staged rollout, centralized monitoring, and regular detection testing.

---

# 18. Official learning resources

Use these resources as your reference when moving from a lab to production.

1. **Installation and Kubernetes deployment:** [Falco deployment documentation](https://falco.org/docs/getting-started/deployment/) — Helm installation and Kubernetes deployment guidance. [Falco](https://falco.org/docs/getting-started/deployment/?utm_source=chatgpt.com)

2. **Recommended Kubernetes management approach:** [Falco Operator](https://falco.org/docs/setup/operator/) — declarative management of Falco instances, rules, plugins, and configuration. [Falco](https://falco.org/docs/setup/operator/?utm_source=chatgpt.com)

3. **First practical lab:** [Falco Kubernetes quickstart](https://falco.org/docs/getting-started/falco-kubernetes-quickstart/) — install Falco, trigger a detection, and create a custom rule. [Falco](https://falco.org/docs/getting-started/falco-kubernetes-quickstart/?utm_source=chatgpt.com)

4. **Rule development:** [Custom ruleset documentation](https://falco.org/docs/concepts/rules/custom-ruleset/) — conditions, rule ordering, macros, and exceptions. [Falco](https://falco.org/docs/concepts/rules/custom-ruleset/?utm_source=chatgpt.com)

5. **Alert integration:** [Falco outputs](https://falco.org/docs/concepts/outputs/) — configure event outputs and integrations. [Falco](https://falco.org/docs/concepts/outputs/?utm_source=chatgpt.com)

---

## Final recommendation

For your DevOps/SRE learning path, follow this order:

1. Understand Linux processes, syscalls, containers, and Kubernetes namespaces.
2. Install Falco on a Linux-backed test cluster.
3. Learn how to interpret built-in security alerts.
4. Write and validate custom rules.
5. Forward events to a central security destination.
6. Integrate detection testing into CI/CD.
7. Practice correlating Falco alerts with Kubernetes audit events and AWS CloudTrail.
8. Implement production monitoring, staged upgrades, and tested incident-response procedures.

**The most important concept to remember:** Falco helps you detect suspicious behavior after workloads start running. A production-grade security architecture combines that visibility with preventive controls, centralized investigation, and a well-tested incident-response process.
