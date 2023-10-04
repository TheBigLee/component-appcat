local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local com = import 'lib/commodore.libjsonnet';
local params = inv.parameters.appcat;
local controllersParams = params.controller;

local image = params.images.appcat;
local loadManifest(manifest) = std.parseJson(kap.yaml_load('appcat/manifests/' + image.tag + '/config/controller/' + manifest));

local serviceAccount = loadManifest('service-account.yaml') {
  metadata+: {
    namespace: controllersParams.namespace,
  },
};

local roleLeaderElection = loadManifest('role-leader-election.yaml') {
  metadata+: {
    namespace: controllersParams.namespace,
  },
};

local roleBindingLeaderElection = loadManifest('role-binding-leader-election.yaml') {
  metadata+: {
    namespace: controllersParams.namespace,
  },
  subjects: [
    super.subjects[0] {
      namespace: controllersParams.namespace,
    },
  ],
};

local clusterRole = loadManifest('cluster-role.yaml');

local clusterRoleBinding = loadManifest('cluster-role-binding.yaml') {
  subjects: [
    super.subjects[0] {
      namespace: controllersParams.namespace,
    },
  ],
};

local mergedArgs = controllersParams.extraArgs + [
  '--quotas=' + std.toString(params.quotasEnabled),
];

local mergedEnv = com.envList(controllersParams.extraEnv) + [
  {
    name: 'PLANS_NAMESPACE',
    value: params.namespace,
  },
];

local controller = loadManifest('deployment.yaml') {
  metadata+: {
    namespace: controllersParams.namespace,
  },
  spec+: {
    replicas: 2,
    template+: {
      spec+: {
        volumes: [
          {
            name: 'webhook-certs',
            secret: {
              secretName: controllersParams.tls.certSecretName,
            },
          },
        ],
        containers: [
          if c.name == 'manager' then
            c {
              image: common.GetAppCatImageString(),
              args+: mergedArgs,
              env+: mergedEnv,
              resources: controllersParams.resources,
              volumeMounts+: [
                {
                  name: 'webhook-certs',
                  mountPath: '/etc/webhook/certs',
                },
              ],
            }
          else
            c
          for c in super.containers
        ],
      },
    },
  },
};

local webhookService = loadManifest('webhook-service.yaml') {
  metadata+: {
    name: 'webhook-service',
    namespace: controllersParams.namespace,
  },
};

local webhookIssuer = {
  apiVersion: 'cert-manager.io/v1',
  kind: 'Issuer',
  metadata: {
    name: 'webhook-server-issuer',
    namespace: params.namespace,
  },
  spec: {
    selfSigned: {},
  },
};

local webhookCertificate = {
  apiVersion: 'cert-manager.io/v1',
  kind: 'Certificate',
  metadata: {
    name: 'webhook-certificate',
    namespace: params.namespace,
  },
  spec: {
    dnsNames: [ webhookService.metadata.name + '.' + params.namespace + '.svc' ],
    duration: '87600h0m0s',
    issuerRef: {
      group: 'cert-manager.io',
      kind: 'Issuer',
      name: webhookIssuer.metadata.name,
    },
    privateKey: {
      algorithm: 'RSA',
      encoding: 'PKCS1',
      size: 4096,
    },
    renewBefore: '2400h0m0s',
    secretName: controllersParams.tls.certSecretName,
    subject: {
      organizations: [ 'vshn-appcat' ],
    },
    usages: [
      'server auth',
      'client auth',
    ],
  },
};

local pgWebhook = loadManifest('pg-webhook.yaml') {
  metadata+: {
    name: 'appcat-pg-validation',
    annotations+: {
      'cert-manager.io/inject-ca-from': params.namespace + '/' + webhookCertificate.metadata.name,
    },
  },
  webhooks: [
    if w.name == 'postgresql.vshn.appcat.vshn.io' then
      w {
        clientConfig+: {
          service+: {
            namespace: controllersParams.namespace,
          },
        },
      }
    else
      w
    for w in super.webhooks
  ],
};

local redisWebhook = loadManifest('redis-webhook.yaml') {
  metadata+: {
    name: 'appcat-redis-validation',
    annotations+: {
      'cert-manager.io/inject-ca-from': params.namespace + '/' + webhookCertificate.metadata.name,
    },
  },
  webhooks: [
    if w.name == 'vshnredis.vshn.appcat.vshn.io' then
      w {
        clientConfig+: {
          service+: {
            namespace: controllersParams.namespace,
          },
        },
      }
    else
      w
    for w in super.webhooks
  ],
};

if controllersParams.enabled then {
  'controllers/appcat/10_role_leader_election': roleLeaderElection,
  'controllers/appcat/10_cluster_role': clusterRole,
  'controllers/appcat/10_role_binding_leader_election': roleBindingLeaderElection,
  'controllers/appcat/10_cluster_role_binding': clusterRoleBinding,
  'controllers/appcat/10_pg_webhooks': pgWebhook,
  'controllers/appcat/10_redis_webhooks': redisWebhook,
  'controllers/appcat/10_webhook_service': webhookService,
  'controllers/appcat/10_webhook_issuer': webhookIssuer,
  'controllers/appcat/10_webhook_certificate': webhookCertificate,
  'controllers/appcat/20_service_account': serviceAccount,
  'controllers/appcat/30_deployment': controller,
} else {}
