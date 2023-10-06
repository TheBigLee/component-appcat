local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local common = import 'common.libsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local kafkaParams = params.services.exoscale.kafka;

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');

local connectionSecretKeys = [
  'KAFKA_URI',
  'KAFKA_HOST',
  'KAFKA_PORT',
  'KAFKA_NODES',
  'service.cert',
  'service.key',
  'ca.crt',
];

local xrd = xrds.XRDFromCRD(
  'xexoscalekafkas.exoscale.appcat.vshn.io',
  xrds.LoadCRD('exoscale.appcat.vshn.io_exoscalekafkas.yaml', params.images.appcat.tag),
  connectionSecretKeys=connectionSecretKeys,
);


local composition =
  local kafkaBase =
    {
      apiVersion: 'exoscale.crossplane.io/v1',
      kind: 'Kafka',
      metadata: {},
      spec: {
        forProvider: {
          ipFilter: '',
          kafkaSettings: {},
          maintenance: {
            dayOfWeek: '',
            timeOfDay: '',
          },
          size: {
            plan: '',
          },
          terminationProtection: false,
          version: '',
          zone: '',
        },
        providerConfigRef: {
          name: 'exoscale',
        },
        writeConnectionSecretToRef: {
          name: '',
          namespace: kafkaParams.providerSecretNamespace,
        },
      },
    };

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'exoscalekafka.exoscale.appcat.vshn.io') +
  common.SyncOptions +
  common.VshnMetaDBaaSExoscale('Kafka') + {
    metadata+: {
      annotations+: {
        'metadata.appcat.vshn.io/plans': importstr 'exoscale-plans/kafka.json',
      },
    },
  } +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: kafkaParams.secretNamespace,
      resources: [
        {
          base: kafkaBase,
          connectionDetails: comp.conn.AllFromSecretKeys(connectionSecretKeys),
          patches: [
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.name'),

            comp.FromCompositeFieldPath('spec.parameters.service.kafkaSettings', 'spec.forProvider.kafkaSettings'),
            comp.FromCompositeFieldPath('spec.parameters.service.zone', 'spec.forProvider.zone'),
            comp.FromCompositeFieldPath('spec.parameters.network.ipFilter', 'spec.forProvider.ipFilter'),
            comp.FromCompositeFieldPath('spec.parameters.size.plan', 'spec.forProvider.size.plan'),
            comp.FromCompositeFieldPath('spec.parameters.maintenance.dayOfWeek', 'spec.forProvider.maintenance.dayOfWeek'),
            comp.FromCompositeFieldPath('spec.parameters.maintenance.timeOfDay', 'spec.forProvider.maintenance.timeOfDay'),
            comp.FromCompositeFieldPath('spec.parameters.service.version', 'spec.forProvider.version'),
            comp.ToCompositeFieldPath('status.atProvider.version', 'status.version'),
          ],
        },
      ],
    },
  };

// OpenShift template configuration
local templateObject = kube._Object('exoscale.appcat.vshn.io/v1', 'ExoscaleKafka', '${INSTANCE_NAME}') + {
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

local templateDescription = 'Apache Kafka is an open-source distributed event streaming platform used by thousands of companies for high-performance data pipelines, streaming analytics, data integration, and mission-critical applications.';
local templateMessage = 'Your Kafka by Exoscale instance is being provisioned, please see ${SECRET_NAME} for access.';

local osTemplate =
  common.OpenShiftTemplate('kafkabyexoscale',
                           'Kafka',
                           templateDescription,
                           'icon-other-unknown',
                           'database,nosql,kafka',
                           templateMessage,
                           'Exoscale',
                           'https://vs.hn/exo-kafka') + {
    objects: [
      templateObject,
    ],
    parameters: [
      {
        name: 'PLAN',
        value: 'startup-2',
      },
      {
        name: 'SECRET_NAME',
        value: 'kafka-credentials',
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

if params.services.exoscale.enabled && kafkaParams.enabled then {
  '20_xrd_exoscale_kafka': xrd,
  '20_rbac_exoscale_kafka': xrds.CompositeClusterRoles(xrd),
  '21_composition_exoscale_kafka': composition,
  [if isOpenshift then '21_openshift_template_kafka_exoscale']: osTemplate,
} else {}
