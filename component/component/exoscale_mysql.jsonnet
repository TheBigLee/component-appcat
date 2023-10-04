local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local common = import 'common.libsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local mysqlParams = params.services.exoscale.mysql;

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');

local connectionSecretKeys = [
  'MYSQL_URL',
  'MYSQL_DB',
  'MYSQL_HOST',
  'MYSQL_PORT',
  'MYSQL_USER',
  'MYSQL_PASSWORD',
  'ca.crt',
];

local xrd = xrds.XRDFromCRD(
  'xexoscalemysqls.exoscale.appcat.vshn.io',
  xrds.LoadCRD('exoscale.appcat.vshn.io_exoscalemysqls.yaml', params.images.appcat.tag),
  defaultComposition='exoscalemysql.exoscale.appcat.vshn.io',
  connectionSecretKeys=connectionSecretKeys,
);


local composition =
  local mysqlBase =
    {
      apiVersion: 'exoscale.crossplane.io/v1',
      kind: 'MySQL',
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
          mysqlSettings: {},
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
          namespace: mysqlParams.providerSecretNamespace,
        },
      },
    };

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'exoscalemysql.exoscale.appcat.vshn.io') +
  common.SyncOptions +
  common.VshnMetaDBaaSExoscale('MySQL') + {
    metadata+: {
      annotations+: {
        'metadata.appcat.vshn.io/plans': importstr 'exoscale-plans/mysql.json',
      },
    },
  } +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: mysqlParams.secretNamespace,
      resources: [
        {
          base: mysqlBase,
          connectionDetails: comp.conn.AllFromSecretKeys(connectionSecretKeys),
          patches: [
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.name'),

            comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.forProvider.version'),
            comp.FromCompositeFieldPath('spec.parameters.service.mysqlSettings', 'spec.forProvider.mysqlSettings'),
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
local templateObject = kube._Object('exoscale.appcat.vshn.io/v1', 'ExoscaleMySQL', '${INSTANCE_NAME}') + {
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

local templateDescription = 'The world’s most popular open-source database.';
local templateMessage = 'Your MySQL by Exoscale instance is being provisioned, please see ${SECRET_NAME} for access.';

local osTemplate =
  common.OpenShiftTemplate('mysqlbyexoscale',
                           'MySQL',
                           templateDescription,
                           'icon-mysql-database',
                           'database,sql,mysql',
                           templateMessage,
                           'Exoscale',
                           'https://vs.hn/exo-mysql') + {
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
        value: 'mysql-credentials',
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
        value: '8',
      },
    ],
  };

if params.services.exoscale.enabled && mysqlParams.enabled then {
  '20_xrd_exoscale_mysql': xrd,
  '20_rbac_exoscale_mysql': xrds.CompositeClusterRoles(xrd),
  '21_composition_exoscale_mysql': composition,
  [if isOpenshift then '21_openshift_template_mysql_exoscale']: osTemplate,
} else {}
