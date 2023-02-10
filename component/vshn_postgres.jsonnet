local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local common = import 'common.libsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local pgParams = params.services.vshn.postgres;

local defaultDB = 'postgres';
local defaultUser = 'postgres';
local defaultPort = '5432';


local serviceNameLabelKey = 'appcat.vshn.io/servicename';
local serviceNamespaceLabelKey = 'appcat.vshn.io/claim-namespace';

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
  'xvshnpostgresqls.vshn.appcat.vshn.io',
  xrds.LoadCRD('vshn.appcat.vshn.io_vshnpostgresqls.yaml'),
  defaultComposition='vshnpostgres.vshn.appcat.vshn.io',
  connectionSecretKeys=connectionSecretKeys,
);


local composition =
  local namespace = comp.KubeObject('v1', 'Namespace') +
                    {
                      spec+: {
                        forProvider+: {
                          manifest+: {
                            metadata: {
                              name: '',
                              labels: {
                                [serviceNameLabelKey]: 'postgresql-standalone',
                                [serviceNamespaceLabelKey]: '',
                              },
                            },
                          },
                        },
                      },
                    };

  local sgInstanceProfile = comp.KubeObject('stackgres.io/v1', 'SGInstanceProfile') +
                            {
                              spec+: {
                                forProvider+: {
                                  manifest+: {
                                    metadata: {},
                                    spec: {
                                      cpu: '',
                                      memory: '',
                                      initContainers: {
                                        'pgbouncer-auth-file': {
                                          cpu: '100m',
                                          memory: '100Mi',
                                        },
                                        'relocate-binaries': {
                                          cpu: '100m',
                                          memory: '100Mi',
                                        },
                                        'setup-scripts': {
                                          cpu: '100m',
                                          memory: '100Mi',
                                        },
                                        'setup-arbitrary-user': {
                                          cpu: '100m',
                                          memory: '100Mi',
                                        },
                                        'cluster-reconciliation-cycle': {
                                          cpu: '100m',
                                          memory: '100Mi',
                                        },
                                      },
                                    },
                                  },
                                },
                              },
                            };

  local sgPostgresConfig = comp.KubeObject('stackgres.io/v1', 'SGPostgresConfig') +
                           {
                             spec+: {
                               forProvider+: {
                                 manifest+: {
                                   metadata: {},
                                   spec: {
                                     postgresVersion: '',
                                     'postgresql.conf': {},
                                   },
                                 },
                               },
                             },
                           };

  local sgCluster = comp.KubeObject('stackgres.io/v1', 'SGCluster') +
                    {
                      spec+: {
                        forProvider+: {
                          manifest+: {
                            metadata: {},
                            spec: {
                              instances: 1,
                              sgInstanceProfile: '',
                              configurations: {
                                sgPostgresConfig: '',
                              },
                              postgres: {
                                version: '',
                              },
                              pods: {
                                persistentVolume: {
                                  size: '',
                                },
                              },
                            },
                          },
                        },
                      },
                    };

  local secret = comp.KubeObject('v1', 'Secret') +
                 {
                   spec+: {
                     forProvider+: {
                       manifest+: {
                         metadata: {},
                         stringData: {
                           POSTGRESQL_USER: defaultUser,
                           POSTGRESQL_PORT: defaultPort,
                           POSTGRESQL_DB: defaultDB,
                           POSTGRESQL_HOST: '',
                         },
                       },
                     },
                     references: [
                       {
                         patchesFrom: {
                           apiVersion: 'v1',
                           kind: 'Secret',
                           namespace: '',
                           name: '',
                           fieldPath: 'data.superuser-password',
                         },
                         toFieldPath: 'data.POSTGRESQL_PASSWORD',
                       },
                     ],
                     // Make crossplane aware of the connection secret we are creating in this object
                     writeConnectionSecretToRef: {
                       name: '',
                       namespace: '',
                     },
                   },
                 };

  local networkPolicy = comp.KubeObject('networking.k8s.io/v1', 'NetworkPolicy') +
                        {
                          spec+: {
                            forProvider+: {
                              manifest+: {
                                metadata: {},
                                spec: {
                                  policyTypes: [
                                    'Ingress',
                                  ],
                                  podSelector: {},
                                  ingress: [
                                    {
                                      from: [
                                        {
                                          namespaceSelector: {
                                            matchLabels: {
                                              'kubernetes.io/metadata.name': '',
                                            },
                                          },
                                        },
                                      ],
                                    },
                                  ],
                                },
                              },
                            },
                          },
                        };

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'vshnpostgres.vshn.appcat.vshn.io') +
  common.SyncOptions +
  common.VshnMetaVshn('PostgreSQL', 'standalone') +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: pgParams.secretNamespace,
      resources: [
        {
          base: namespace {
            spec+: {
              managementPolicy: 'Observe',
            },
          },
          patches: [
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'ns-observer'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.manifest.metadata.name'),
            comp.ToCompositeFieldPath('status.atProvider.manifest.metadata.labels[appuio.io/organization]', 'metadata.labels[appuio.io/organization]'),
          ],
        },
        {
          base: namespace,
          patches: [
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'vshn-postgresql'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.manifest.metadata.labels[%s]' % serviceNamespaceLabelKey),
            comp.FromCompositeFieldPath('metadata.labels[appuio.io/organization]', 'spec.forProvider.manifest.metadata.labels[appuio.io/organization]'),
          ],
        },
        {
          base: sgInstanceProfile,
          patches: [
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'profile'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),

            comp.FromCompositeFieldPath('spec.parameters.size.memory', 'spec.forProvider.manifest.spec.memory'),
            comp.FromCompositeFieldPath('spec.parameters.size.cpu', 'spec.forProvider.manifest.spec.cpu'),
          ],
        },
        {
          base: sgPostgresConfig,
          patches: [
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'pgconf'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),

            comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.forProvider.manifest.spec.postgresVersion'),
            comp.FromCompositeFieldPath('spec.parameters.service.pgSettings', 'spec.forProvider.manifest.spec[postgresql.conf]'),
          ],
        },
        {
          base: sgCluster,
          patches: [
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'cluster'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),

            comp.FromCompositeFieldPath('spec.parameters.size.disk', 'spec.forProvider.manifest.spec.pods.persistentVolume.size'),
            comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.forProvider.manifest.spec.postgres.version'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.sgInstanceProfile'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.configurations.sgPostgresConfig'),
          ],
        },
        {
          base: secret,
          connectionDetails: comp.conn.AllFromSecretKeys(connectionSecretKeys),
          patches: [
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'connection'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/claim-name]', 'spec.forProvider.manifest.metadata.name', 'connection'),

            comp.CombineCompositeFromTwoFieldPaths('metadata.labels[crossplane.io/composite]', 'metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.stringData.POSTGRESQL_HOST', '%s.vshn-postgresql-%s.svc.cluster.local'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.references[0].patchesFrom.namespace', 'vshn-postgresql'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.references[0].patchesFrom.name'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.namespace', 'vshn-postgresql'),
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/claim-name]', 'spec.writeConnectionSecretToRef.name', 'connection'),
          ],
        },
      ] + if pgParams.enableNetworkPolicy == true then [
        {
          base: networkPolicy,
          patches: [
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'network-policy'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
            comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name', 'allow-from-claim-namespace'),

            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.manifest.spec.ingress[0].from[0].namespaceSelector.matchLabels[kubernetes.io/metadata.name]'),
          ],
        },
      ] else [],
    },
  };


if params.services.vshn.enabled && pgParams.enabled then {
  '20_xrd_vshn_postgres': xrd,
  '20_rbac_vshn_postgres': xrds.CompositeClusterRoles(xrd),
  '21_composition_vshn_postgres': composition,
} else {}
