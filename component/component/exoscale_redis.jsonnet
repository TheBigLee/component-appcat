local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local common = import 'common.libsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local redisParams = params.services.exoscale.redis;

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');

local connectionSecretKeys = [
  'REDIS_HOST',
  'REDIS_PORT',
  'REDIS_USERNAME',
  'REDIS_PASSWORD',
  'REDIS_URL',
];

local xrd = xrds.XRDFromCRD(
  'xexoscaleredis.exoscale.appcat.vshn.io',
  xrds.LoadCRD('exoscale.appcat.vshn.io_exoscaleredis.yaml', params.images.appcat.tag),
  defaultComposition='exoscaleredis.exoscale.appcat.vshn.io',
  connectionSecretKeys=connectionSecretKeys,
);


local composition =
  local redisBase =
    {
      apiVersion: 'exoscale.crossplane.io/v1',
      kind: 'Redis',
      metadata: {},
      spec: {
        forProvider: {
          ipFilter: '',
          maintenance: {
            dayOfWeek: '',
            timeOfDay: '',
          },
          redisSettings: {},
          size: {
            plan: '',
          },
          terminationProtection: false,
          zone: '',
        },
        providerConfigRef: {
          name: 'exoscale',
        },
        writeConnectionSecretToRef: {
          name: '',
          namespace: redisParams.providerSecretNamespace,
        },
      },
    };

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'exoscaleredis.exoscale.appcat.vshn.io') +
  common.SyncOptions +
  common.VshnMetaDBaaSExoscale('Redis') + {
    metadata+: {
      annotations+: {
        'metadata.appcat.vshn.io/plans': importstr 'exoscale-plans/redis.json',
      },
    },
  } +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: redisParams.secretNamespace,
      resources: [
        {
          base: redisBase,
          connectionDetails: comp.conn.AllFromSecretKeys(connectionSecretKeys),
          patches: [
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.name'),

            comp.FromCompositeFieldPath('spec.parameters.service.redisSettings', 'spec.forProvider.redisSettings'),
            comp.FromCompositeFieldPath('spec.parameters.service.zone', 'spec.forProvider.zone'),
            comp.FromCompositeFieldPath('spec.parameters.network.ipFilter', 'spec.forProvider.ipFilter'),
            comp.FromCompositeFieldPath('spec.parameters.size.plan', 'spec.forProvider.size.plan'),
            comp.FromCompositeFieldPath('spec.parameters.maintenance.dayOfWeek', 'spec.forProvider.maintenance.dayOfWeek'),
            comp.FromCompositeFieldPath('spec.parameters.maintenance.timeOfDay', 'spec.forProvider.maintenance.timeOfDay'),
          ],
        },
      ],
    },
  };

// OpenShift template configuration
local templateObject = kube._Object('exoscale.appcat.vshn.io/v1', 'ExoscaleRedis', '${INSTANCE_NAME}') + {
  spec: {
    parameters: {
      service: {
        zone: '${ZONE}',
      },
      size: {
        plan: '${PLAN}',
      },
    },
    writeConnectionSecretToRef: {
      name: '${SECRET_NAME}',
    },
  },
};

local templateDescription = 'The open source, in-memory data store used by millions of developers as a database, cache, streaming engine, and message broker.';
local templateMessage = 'Your Redis by Exoscale instance is being provisioned, please see ${SECRET_NAME} for access.';

local osTemplate =
  common.OpenShiftTemplate('redisbyexoscale',
                           'Redis',
                           templateDescription,
                           'icon-redis',
                           'database,nosql',
                           templateMessage,
                           'Exoscale',
                           'https://vs.hn/exo-redis') + {
    objects: [
      templateObject,
    ],
    parameters: [
      {
        name: 'PLAN',
        value: 'startup-4',
      },
      {
        name: 'SECRET_NAME',
        value: 'redis-credentials',
      },
      {
        name: 'INSTANCE_NAME',
      },
      {
        name: 'ZONE',
        value: 'ch-dk-2',
      },
    ],
  };

if params.services.exoscale.enabled && redisParams.enabled then {
  '20_xrd_exoscale_redis': xrd,
  '20_rbac_exoscale_redis': xrds.CompositeClusterRoles(xrd),
  '21_composition_exoscale_redis': composition,
  [if isOpenshift then '21_openshift_template_redis_exoscale']: osTemplate,
} else {}
