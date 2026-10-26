# Workflow architecture diagrams

How Temporal work is started, served and scaled, and how one worker release
rolls out.

[Architecture index](../README.md)

## The Temporal work layer

Who starts each workflow, which queue and worker serve it, and which controllers
own each worker's builds and replicas. Explained in
[`api/workflows.md`](../../api/workflows.md).

<p align="center"><a href="temporal-keda.svg"><img src="temporal-keda.svg" alt="Workflow starters, Temporal task queues, workers and the controllers that own their builds and replicas" width="960"></a></p>
<p align="center"><sub>Source <a href="temporal-keda.drawio"><code>temporal-keda.drawio</code></a> · <a href="img/temporal-keda.png">PNG</a></sub></p>

## One worker release

The builds, the Progressive rollout and the per-build KEDA scaling while
order-fulfillment ramps from build A to build B. Explained in
[`api/workflows.md`](../../api/workflows.md) ·
[`api/temporal.md` § Worker Deployment Versioning](../../api/temporal.md#worker-deployment-versioning-as-built).

<p align="center"><a href="temporal-worker-versions.svg"><img src="temporal-worker-versions.svg" alt="order-fulfillment worker builds A and B during a Progressive rollout with per-build KEDA scaling" width="960"></a></p>
<p align="center"><sub>Source <a href="temporal-worker-versions.drawio"><code>temporal-worker-versions.drawio</code></a> · <a href="img/temporal-worker-versions.png">PNG</a></sub></p>
