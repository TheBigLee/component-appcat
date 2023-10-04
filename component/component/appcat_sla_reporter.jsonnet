local common = import 'common.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appcat;
local slos_params = params.slos;
local sla_reporter_params = slos_params.sla_reporter;
local mimir_endpoint = 'http://' + sla_reporter_params.slo_mimir_svc + '.' + sla_reporter_params.slo_mimir_namespace + '.svc.cluster.local:8080/prometheus';

local CronJob = kube.CronJob('appcat-sla-reporter') {
  metadata+: {
    namespace: slos_params.namespace,
  },
  spec+: {
    schedule: sla_reporter_params.schedule,
    failedJobsHistoryLimit: 3,
    successfulJobsHistoryLimit: 0,
    jobTemplate+: {
      spec+: {
        template+: {
          spec+: {
            containers: [
              {
                name: 'sla-reporter',
                image: common.GetAppCatImageString(),
                resources: sla_reporter_params.resources,
                args: [
                  'slareport',
                  '--previousmonth',
                  '--mimirorg',
                  sla_reporter_params.mimir_organization,
                ],
                envFrom: [
                  {
                    secretRef: {
                      name: 'appcat-sla-reports-creds',
                    },
                  },
                ],
                env: [
                  {
                    name: 'PROM_URL',
                    value: mimir_endpoint,
                  },
                ],
              },
            ],
          },
        },
      },
    },
  },
};

local ObjectStorage = kube._Object('appcat.vshn.io/v1', 'ObjectBucket', 'appcat-sla-reports') {
  metadata: {
    namespace: slos_params.namespace,
    name: 'appcat-sla-reports',
    annotations: common.ArgoCDAnnotations(),
  },
  spec: {
    parameters: {
      bucketName: 'appcat-sla-reports',
      region: sla_reporter_params.bucket_region,
    },
    writeConnectionSecretToRef: {
      name: 'appcat-sla-reports-creds',
    },
  },
};

local netPol = kube.NetworkPolicy('allow-from-%s' % slos_params.namespace) {
  metadata+: {
    namespace: sla_reporter_params.slo_mimir_namespace,
  },
  spec+: {
    ingress_: {
      allowFromReportNs: {
        from: [
          {
            namespaceSelector: {
              matchLabels: {
                name: slos_params.namespace,
              },
            },
          },
        ],
      },
    },
  },
};

if sla_reporter_params.enabled == true then {
  '01_cronjob': CronJob,
  '02_object_bucket': ObjectStorage,
  '03_network_policy': netPol,
} else {}
