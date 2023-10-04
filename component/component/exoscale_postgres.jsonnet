local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local common = import 'common.libsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local pgParams = params.services.exoscale.postgres;

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');

local connectionSecretKeys = [
  'POSTGRESQL_URL',
  'POSTGRESQL_DB',
  'POSTGRESQL_HOST',
  'POSTGRESQL_PORT',
  'POSTGRESQL_USER',
  'POSTGRESQL_PASSWORD',
  'ca.crt',
];

local xrd = xrds.XRDFromCRD(
  'xexoscalepostgresqls.exoscale.appcat.vshn.io',
  xrds.LoadCRD('exoscale.appcat.vshn.io_exoscalepostgresqls.yaml', params.images.appcat.tag),
  defaultComposition='exoscalepostgres.exoscale.appcat.vshn.io',
  connectionSecretKeys=connectionSecretKeys,
);


local composition =
  local pgBase =
    {
      apiVersion: 'exoscale.crossplane.io/v1',
      kind: 'PostgreSQL',
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
          pgSettings: {},
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
          namespace: pgParams.providerSecretNamespace,
        },
      },
    };

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'exoscalepostgres.exoscale.appcat.vshn.io') +
  common.SyncOptions +
  common.VshnMetaDBaaSExoscale('PostgreSQL') + {
    metadata+: {
      annotations+: {
        'metadata.appcat.vshn.io/plans': importstr 'exoscale-plans/pg.json',
      },
    },
  } +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: pgParams.secretNamespace,
      resources: [
        {
          base: pgBase,
          connectionDetails: comp.conn.AllFromSecretKeys(connectionSecretKeys),
          patches: [
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.name'),

            comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.forProvider.version'),
            comp.FromCompositeFieldPath('spec.parameters.service.pgSettings', 'spec.forProvider.pgSettings'),
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
local templateObject = kube._Object('exoscale.appcat.vshn.io/v1', 'ExoscalePostgreSQL', '${INSTANCE_NAME}') + {
  spec: {
    parameters: {
      service: {
        majorVersion: '${MAJOR_VERSION}',
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

local templateDescription = 'PostgreSQL is a powerful, open source object-relational database system that uses and extends the SQL language combined with many features that safely store and scale the most complicated data workloads. The origins of PostgreSQL date back to 1986 as part of the POSTGRES project at the University of California at Berkeley and has more than 30 years of active development on the core platform.';
local templateMessage = 'Your PostgreSQL by Exoscale instance is being provisioned, please see ${SECRET_NAME} for access.';

local osTemplate =
  common.OpenShiftTemplate('postgresqlbyexoscale',
                           'PostgreSQL',
                           templateDescription,
                           'icon-postgresql',
                           'database,sql,postgresql',
                           templateMessage,
                           'Exoscale',
                           'https://vs.hn/exo-postgresql') + {
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
        value: 'postgresql-credentials',
      },
      {
        name: 'INSTANCE_NAME',
      },
      {
        name: 'MAJOR_VERSION',
        value: '14',
      },
      {
        name: 'ZONE',
        value: 'ch-dk-2',
      },
    ],
  };

if params.services.exoscale.enabled && pgParams.enabled then {
  '20_xrd_exoscale_postgres': xrd,
  '20_rbac_exoscale_postgres': xrds.CompositeClusterRoles(xrd),
  '21_composition_exoscale_postgres': composition,
  [if isOpenshift then '21_openshift_template_postgresql_exoscale']: osTemplate,
} else {}
