local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local common = import 'common.libsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local osParams = params.services.exoscale.opensearch;

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');

local connectionSecretKeys = [
  'OPENSEARCH_USER',
  'OPENSEARCH_PASSWORD',
  'OPENSEARCH_DASHBOARD_URI',
  'OPENSEARCH_URI',
  'OPENSEARCH_HOST',
  'OPENSEARCH_PORT',
];

local xrd = xrds.XRDFromCRD(
  'xexoscaleopensearches.exoscale.appcat.vshn.io',
  xrds.LoadCRD('exoscale.appcat.vshn.io_exoscaleopensearches.yaml', params.images.appcat.tag),
  defaultComposition='exoscaleopensearch.exoscale.appcat.vshn.io',
  connectionSecretKeys=connectionSecretKeys,
);


local composition =
  local osBase =
    {
      apiVersion: 'exoscale.crossplane.io/v1',
      kind: 'OpenSearch',
      metadata: {},
      spec: {
        forProvider: {
          backup: {
            timeOfDay: '',
          },
          ipFilter: '',
          maintenance: {
            dayOfWeek: '',
            timeOfDay: '',
          },
          opensearchSettings: {},
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
          namespace: osParams.providerSecretNamespace,
        },
      },
    };

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'exoscaleopensearch.exoscale.appcat.vshn.io') +
  common.SyncOptions +
  common.VshnMetaDBaaSExoscale('OpenSearch') + {
    metadata+: {
      annotations+: {
        'metadata.appcat.vshn.io/plans': importstr 'exoscale-plans/opensearch.json',
      },
    },
  } +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: osParams.secretNamespace,
      resources: [
        {
          base: osBase,
          connectionDetails: comp.conn.AllFromSecretKeys(connectionSecretKeys),
          patches: [
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.name'),

            comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.forProvider.majorVersion'),
            comp.FromCompositeFieldPath('spec.parameters.service.opensearchSettings', 'spec.forProvider.openSearchSettings'),
            comp.FromCompositeFieldPath('spec.parameters.service.zone', 'spec.forProvider.zone'),
            comp.FromCompositeFieldPath('spec.parameters.network.ipFilter', 'spec.forProvider.ipFilter'),
            comp.FromCompositeFieldPath('spec.parameters.size.plan', 'spec.forProvider.size.plan'),
            comp.FromCompositeFieldPath('spec.parameters.maintenance.dayOfWeek', 'spec.forProvider.maintenance.dayOfWeek'),
            comp.FromCompositeFieldPath('spec.parameters.maintenance.timeOfDay', 'spec.forProvider.maintenance.timeOfDay'),
            comp.FromCompositeFieldPath('spec.parameters.backup.timeOfDay', 'spec.forProvider.backup.timeOfDay'),
          ],
        },
      ],
    },
  };

// OpenShift template configuration
local templateObject = kube._Object('exoscale.appcat.vshn.io/v1', 'ExoscaleOpenSearch', '${INSTANCE_NAME}') + {
  spec: {
    parameters: {
      service: {
        zone: '${ZONE}',
        majorVersion: '${MAJOR_VERSION}',
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

local templateDescription = 'OpenSearch is a community-driven, open-source search and analytics suite used by developers to ingest, search, visualize, and analyze data.';
local templateMessage = 'Your OpenSearch by Exoscale instance is being provisioned, please see ${SECRET_NAME} for access.';

local osTemplate =
  common.OpenShiftTemplate('opensearchbyexoscale',
                           'OpenSearch',
                           templateDescription,
                           'icon-elastic',
                           'database,nosql,opensearch,search',
                           templateMessage,
                           'Exoscale',
                           'https://vs.hn/exo-opensearch') + {
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
        value: 'opensearch-credentials',
      },
      {
        name: 'INSTANCE_NAME',
      },
      {
        name: 'ZONE',
        value: 'ch-dk-2',
      },
      {
        name: 'MAJOR_VERSION',
        value: '2',
      },
    ],
  };

if params.services.exoscale.enabled && osParams.enabled then {
  '20_xrd_exoscale_opensearch': xrd,
  '20_rbac_exoscale_opensearch': xrds.CompositeClusterRoles(xrd),
  '21_composition_exoscale_opensearch': composition,
  [if isOpenshift then '21_openshift_template_opensearch_exoscale']: osTemplate,
} else {}
