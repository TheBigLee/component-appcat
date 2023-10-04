local common = import 'common.libsonnet';
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

local certificateSecretName = 'tls-certificate';

local serviceNameLabelKey = 'appcat.vshn.io/servicename';
local serviceNamespaceLabelKey = 'appcat.vshn.io/claim-namespace';
local slaLabelKey = 'appcat.vshn.io/sla';

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');

// Filter out disabled plans
local pgPlans = common.FilterDisabledParams(pgParams.plans);

local connectionSecretKeys = [
  'ca.crt',
  'tls.crt',
  'tls.key',
  'POSTGRESQL_URL',
  'POSTGRESQL_DB',
  'POSTGRESQL_HOST',
  'POSTGRESQL_PORT',
  'POSTGRESQL_USER',
  'POSTGRESQL_PASSWORD',
  'LOADBALANCER_IP',
];

local xrd = xrds.XRDFromCRD(
  'xvshnpostgresqls.vshn.appcat.vshn.io',
  xrds.LoadCRD('vshn.appcat.vshn.io_vshnpostgresqls.yaml', params.images.appcat.tag),
  defaultComposition='vshnpostgres.vshn.appcat.vshn.io',
  connectionSecretKeys=connectionSecretKeys,
) + xrds.WithPlanDefaults(pgPlans, pgParams.defaultPlan);

local promRulePostgresSLA = common.PromRuleSLA(params.services.vshn.postgres.sla, 'VSHNPostgreSQL');

local restoreServiceAccount = kube.ServiceAccount('copyserviceaccount') + {
  metadata+: {
    namespace: params.services.controlNamespace,
  },
};

local restoreRoleName = 'crossplane:appcat:job:postgres:copybackups';
local restoreRole = kube.ClusterRole(restoreRoleName) {
  rules: [
    {
      apiGroups: [ 'stackgres.io' ],
      resources: [ 'sgbackups', 'sgobjectstorages' ],
      verbs: [ 'get', 'list', 'create' ],
    },
    {
      apiGroups: [ 'vshn.appcat.vshn.io' ],
      resources: [ 'vshnpostgresqls' ],
      verbs: [ 'get' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'secrets' ],
      verbs: [ 'get', 'create' ],
    },
  ],
};

local restoreClusterRoleBinding = kube.ClusterRoleBinding('appcat:job:postgres:copybackup') + {
  roleRef_: restoreRole,
  subjects_: [ restoreServiceAccount ],
};

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
                              [slaLabelKey]: '',
                              'appuio.io/no-rbac-creation': 'true',
                              'appuio.io/organization': 'vshn',
                              'appuio.io/billing-name': 'appcat-postgresql',
                            },
                          },
                        },
                      },
                    },
                  };

local claimNamespaceObserve = {
  name: 'ns-observer',
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
};

local instanceNamespace = {
  name: 'namespace-conditions',
  base: namespace,
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.namespaceConditions'),
    comp.ToCompositeFieldPath('metadata.name', 'status.instanceNamespace'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.manifest.metadata.labels[%s]' % serviceNamespaceLabelKey),
    comp.FromCompositeFieldPath('spec.parameters.service.serviceLevel', 'spec.forProvider.manifest.metadata.labels[appcat.vshn.io/sla]'),
    comp.FromCompositeFieldPath('metadata.labels[appuio.io/organization]', 'spec.forProvider.manifest.metadata.labels[appuio.io/organization]'),
  ],
};

local localca = {
  name: 'local-ca',
  base: comp.KubeObject('cert-manager.io/v1', 'Issuer') +
        {
          spec+: {
            forProvider+: {
              manifest+: {
                metadata: {
                  name: '',
                  namespace: '',
                },
                spec: {
                  selfSigned: {
                    crlDistributionPoints: [],
                  },
                },
              },
            },
          },
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.localCAConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'localca'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
  ],
};

local certificate = {
  name: 'certificate',
  base: comp.KubeObject('cert-manager.io/v1', 'Certificate') +
        {
          spec+: {
            forProvider+: {
              manifest+: {
                metadata: {
                  name: '',
                  namespace: '',
                },
                spec: {
                  secretName: certificateSecretName,
                  duration: '87600h',
                  renewBefore: '2400h',
                  subject: {
                    organizations: [
                      'vshn-appcat',
                    ],
                  },
                  isCA: false,
                  privateKey: {
                    algorithm: 'RSA',
                    encoding: 'PKCS1',
                    size: 4096,
                  },
                  usages: [
                    'server auth',
                    'client auth',
                  ],
                  dnsNames: [
                    'vshn.appcat.vshn.ch',
                  ],
                  issuerRef: {
                    name: '',
                    kind: 'Issuer',
                    group: 'cert-manager.io',
                  },
                },
              },
            },
          },
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.certificateConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'certificate'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.issuerRef.name'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
  ],
};

local sgInstanceProfile = {
  name: 'profile',
  base: comp.KubeObject('stackgres.io/v1', 'SGInstanceProfile') +
        {
          spec+: {
            forProvider+: {
              manifest+: {
                metadata: {},
                spec: {
                  cpu: '',
                  memory: '',
                  requests: {
                    cpu: null,
                    memory: null,
                  },
                  containers: {
                    'backup.create-backup': {
                      cpu: pgParams.sideCars.createBackup.requests.cpu,
                      memory: pgParams.sideCars.createBackup.requests.memory,
                    },
                    'cluster-controller': {
                      cpu: pgParams.sideCars.clusterController.requests.cpu,
                      memory: pgParams.sideCars.clusterController.requests.memory,
                    },
                    'dbops.run-dbops': {
                      cpu: pgParams.sideCars.runDbops.requests.cpu,
                      memory: pgParams.sideCars.runDbops.requests.memory,
                    },
                    'dbops.set-dbops-result': {
                      cpu: pgParams.sideCars.setDbopsResult.requests.cpu,
                      memory: pgParams.sideCars.setDbopsResult.requests.memory,
                    },
                    envoy: {
                      cpu: pgParams.sideCars.envoy.requests.cpu,
                      memory: pgParams.sideCars.envoy.requests.memory,
                    },
                    pgbouncer: {
                      cpu: pgParams.sideCars.pgbouncer.requests.cpu,
                      memory: pgParams.sideCars.pgbouncer.requests.memory,
                    },
                    'postgres-util': {
                      cpu: pgParams.sideCars.postgresUtil.requests.cpu,
                      memory: pgParams.sideCars.postgresUtil.requests.memory,
                    },
                    'prometheus-postgres-exporter': {
                      cpu: pgParams.sideCars.prometheusPostgresExporter.requests.cpu,
                      memory: pgParams.sideCars.prometheusPostgresExporter.requests.memory,
                    },
                  },
                  initContainers: {
                    'pgbouncer-auth-file': {
                      cpu: pgParams.initContainers.pgbouncerAuthFile.requests.cpu,
                      memory: pgParams.initContainers.pgbouncerAuthFile.requests.memory,
                    },
                    'relocate-binaries': {
                      cpu: pgParams.initContainers.relocateBinaries.requests.cpu,
                      memory: pgParams.initContainers.relocateBinaries.requests.memory,
                    },
                    'setup-scripts': {
                      cpu: pgParams.initContainers.setupScripts.requests.cpu,
                      memory: pgParams.initContainers.setupScripts.requests.memory,
                    },
                    'setup-arbitrary-user': {
                      cpu: pgParams.initContainers.setupArbitraryUser.requests.cpu,
                      memory: pgParams.initContainers.setupArbitraryUser.requests.memory,
                    },
                    'cluster-reconciliation-cycle': {
                      cpu: pgParams.initContainers.clusterReconciliationCycle.requests.cpu,
                      memory: pgParams.initContainers.clusterReconciliationCycle.requests.memory,
                    },
                    'dbops.set-dbops-running': {
                      cpu: pgParams.initContainers.setDbopsRunning.requests.cpu,
                      memory: pgParams.initContainers.setDbopsRunning.requests.memory,
                    },
                  },
                },
              },
            },
          },
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.profileConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'profile'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),

    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan', 'spec.forProvider.manifest.spec.cpu', std.mapWithKey(function(key, x) x.size.cpu, pgPlans)),
    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan', 'spec.forProvider.manifest.spec.memory', std.mapWithKey(function(key, x) x.size.memory, pgPlans)),
    comp.FromCompositeFieldPath('spec.parameters.size.memory', 'spec.forProvider.manifest.spec.memory'),
    comp.FromCompositeFieldPath('spec.parameters.size.cpu', 'spec.forProvider.manifest.spec.cpu'),
    comp.FromCompositeFieldPath('spec.parameters.size.requests.memory', 'spec.forProvider.manifest.spec.requests.memory'),
    comp.FromCompositeFieldPath('spec.parameters.size.requests.cpu', 'spec.forProvider.manifest.spec.requests.cpu'),
  ],
};

local sgPostgresConfig = {
  name: 'pg-conf',
  base: comp.KubeObject('stackgres.io/v1', 'SGPostgresConfig') +
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
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.pgconfigConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'pgconf'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),

    comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.forProvider.manifest.spec.postgresVersion'),
    comp.FromCompositeFieldPath('spec.parameters.service.pgSettings', 'spec.forProvider.manifest.spec[postgresql.conf]'),
  ],
};

local sgCluster = {
  name: 'cluster',
  base: comp.KubeObject('stackgres.io/v1', 'SGCluster') +
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
                    backups:
                      [
                        {
                          sgObjectStorage: '',
                          cronSchedule: '',
                          retention: 6,
                        },
                      ],
                  },
                  postgres: {
                    version: '',
                    ssl: {
                      enabled: true,
                      certificateSecretKeySelector: {
                        name: certificateSecretName,
                        key: 'tls.crt',
                      },
                      privateKeySecretKeySelector: {
                        name: certificateSecretName,
                        key: 'tls.key',
                      },
                    },
                  },
                  pods: {
                    persistentVolume: {
                      size: '',
                    },
                  },
                  nonProductionOptions: {
                    enableSetPatroniCpuRequests: true,
                    enableSetPatroniMemoryRequests: true,
                  },
                },
              },
            },
          },
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.pgclusterConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'cluster'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name'),

    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan',
                                                'spec.forProvider.manifest.spec.pods.persistentVolume.size',
                                                std.mapWithKey(function(key, x) x.size.disk, pgPlans)),
    comp.FromCompositeFieldPath('spec.parameters.size.disk', 'spec.forProvider.manifest.spec.pods.persistentVolume.size'),

    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan',
                                                'spec.forProvider.manifest.spec.pods.scheduling.nodeSelector',
                                                std.mapWithKey(function(key, x)
                                                                 std.get(std.get(x, 'scheduling', default={}), 'nodeSelector', default={}),
                                                               pgPlans)),
    comp.FromCompositeFieldPath('spec.parameters.scheduling.nodeSelector', 'spec.forProvider.manifest.spec.pods.scheduling.nodeSelector'),

    comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.forProvider.manifest.spec.postgres.version'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.sgInstanceProfile'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.configurations.sgPostgresConfig'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.configurations.backups[0].sgObjectStorage', 'sgbackup'),

    comp.FromCompositeFieldPath('spec.parameters.backup.schedule', 'spec.forProvider.manifest.spec.configurations.backups[0].cronSchedule'),
    comp.FromCompositeFieldPath('spec.parameters.backup.retention', 'spec.forProvider.manifest.spec.configurations.backups[0].retention'),
  ],
};

local secret = {
  name: 'connection',
  base: comp.KubeObject('v1', 'Secret') +
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
              {
                patchesFrom: {
                  apiVersion: 'v1',
                  kind: 'Secret',
                  name: certificateSecretName,
                  namespace: '',
                  fieldPath: 'data[ca.crt]',
                },
                toFieldPath: 'data[ca.crt]',
              },
              {
                patchesFrom: {
                  apiVersion: 'v1',
                  kind: 'Secret',
                  name: certificateSecretName,
                  namespace: '',
                  fieldPath: 'data[tls.crt]',
                },
                toFieldPath: 'data[tls.crt]',
              },
              {
                patchesFrom: {
                  apiVersion: 'v1',
                  kind: 'Secret',
                  name: certificateSecretName,
                  namespace: '',
                  fieldPath: 'data[tls.key]',
                },
                toFieldPath: 'data[tls.key]',
              },
            ],
            // Make crossplane aware of the connection secret we are creating in this object
            writeConnectionSecretToRef: {
              name: '',
              namespace: '',
            },
          },
        },
  connectionDetails: comp.conn.AllFromSecretKeys(connectionSecretKeys),
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.secretConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'connection'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/claim-name]', 'spec.forProvider.manifest.metadata.name', 'connection'),

    comp.CombineCompositeFromTwoFieldPaths('metadata.labels[crossplane.io/composite]', 'metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.stringData.POSTGRESQL_HOST', '%s.vshn-postgresql-%s.svc.cluster.local'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.references[0].patchesFrom.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.references[0].patchesFrom.name'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/claim-name]', 'spec.writeConnectionSecretToRef.name', 'connection'),

    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.references[1].patchesFrom.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.references[2].patchesFrom.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.references[3].patchesFrom.namespace', 'vshn-postgresql'),
  ],
};

local xobjectBucket = {
  name: 'pg-bucket',
  base: {
    apiVersion: 'appcat.vshn.io/v1',
    kind: 'XObjectBucket',
    metadata: {},
    spec: {
      parameters: {
        bucketName: '',
        region: pgParams.bucket_region,
      },
      writeConnectionSecretToRef: {
        namespace: '',
        name: '',
      },
    },
  },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.objectBackupConfigConditions'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.parameters.bucketName'),

    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.name', 'pgbucket'),
  ],
};

local sgObjectStorage = {
  name: 'sg-backup',
  base: comp.KubeObject('stackgres.io/v1beta1', 'SGObjectStorage') +
        {
          spec+: {
            forProvider+: {
              manifest+: {
                metadata: {
                  name: '',
                  namespace: '',
                },
                spec: {
                  type: 's3Compatible',
                  s3Compatible: {
                    bucket: '',
                    enablePathStyleAddressing: true,
                    region: pgParams.bucket_region,
                    endpoint: pgParams.bucket_endpoint,
                    awsCredentials: {
                      secretKeySelectors: {
                        accessKeyId: {
                          name: '',
                          key: 'AWS_ACCESS_KEY_ID',
                        },
                        secretAccessKey: {
                          name: '',
                          key: 'AWS_SECRET_ACCESS_KEY',
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.objectBucketConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'object-storage'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name', 'sgbackup'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.s3Compatible.bucket'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.spec.writeConnectionSecretToRef.namespace'),

    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.s3Compatible.awsCredentials.secretKeySelectors.accessKeyId.name', 'pgbucket'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.s3Compatible.awsCredentials.secretKeySelectors.secretAccessKey.name', 'pgbucket'),
  ],
};

local networkPolicy = {
  name: 'network-policy',
  base: comp.KubeObject('networking.k8s.io/v1', 'NetworkPolicy') +
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
                        {
                          namespaceSelector: {
                            matchLabels: {
                              'kubernetes.io/metadata.name': params.slos.namespace,
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
        },
  patches: [
    comp.ToCompositeFieldPath('status.conditions', 'status.networkPolicyConditions'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'network-policy'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name', 'allow-from-claim-namespace'),

    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.manifest.spec.ingress[0].from[0].namespaceSelector.matchLabels[kubernetes.io/metadata.name]'),
  ],
};

local copyJob = {
  name: 'copy-job',
  base: comp.KubeObject('batch/v1', 'Job') + {
    spec+: {
      forProvider+: {
        manifest+: {
          metadata+: {
            namespace: params.services.controlNamespace,
          },
          spec: {
            template: {
              spec: {
                ttlSecondsAfterFinished: 100,
                restartPolicy: 'Never',
                serviceAccountName: 'copyserviceaccount',
                containers: [
                  {
                    name: 'copyjob',
                    image: 'bitnami/kubectl:latest',
                    command: [ 'sh', '-c' ],
                    args: [ importstr 'scripts/copy-pg-backup.sh' ],
                    env: [
                      {
                        name: 'CLAIM_NAMESPACE',
                      },
                      {
                        name: 'CLAIM_NAME',
                      },
                      {
                        name: 'BACKUP_NAME',
                      },
                      {
                        name: 'TARGET_NAMESPACE',
                      },
                    ],
                  },
                ],
              },
            },
          },
        },
      },
    },
  },
  patches: [
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'copyjob'),
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.name', 'copyjob'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/claim-namespace]', 'spec.forProvider.manifest.spec.template.spec.containers[0].env[0].value'),
    comp.FromCompositeFieldPath('spec.parameters.restore.claimName', 'spec.forProvider.manifest.spec.template.spec.containers[0].env[1].value'),
    comp.FromCompositeFieldPath('spec.parameters.restore.backupName', 'spec.forProvider.manifest.spec.template.spec.containers[0].env[2].value'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.template.spec.containers[0].env[3].value', 'vshn-postgresql'),
  ],
};

local clusterRestoreConfig = {
  name: 'cluster-restore',
  base+: {
    spec+: {
      references+: [
        {
          dependsOn+: {
            apiVersion: 'stackgres.io/v1',
            kind: 'SGBackup',
          },
        },
      ],
    },
  },
  patches+: [
    comp.FromCompositeFieldPath('spec.parameters.restore.backupName', 'spec.forProvider.manifest.spec.initialData.restore.fromBackup.name'),
    comp.FromCompositeFieldPath('spec.parameters.restore.recoveryTimeStamp', 'spec.forProvider.manifest.spec.initialData.restore.fromBackup.pointInTimeRecovery.restoreToTimestamp'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.references[0].dependsOn.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('spec.parameters.restore.backupName', 'spec.references[0].dependsOn.name'),
  ],
};

local prometheusRule = {
  name: 'prometheusrule',
  base: comp.KubeObject('monitoring.coreos.com/v1', 'PrometheusRule') + {
    spec+: {
      forProvider+: {
        manifest+: {
          metadata: {
            name: 'postgresql-rules',
          },
          local bottomPod(query) = 'label_replace( bottomk(1, %s) * on(namespace) group_left(label_appcat_vshn_io_claim_namespace) kube_namespace_labels, "name", "$1", "namespace", "vshn-postgresql-(.+)-.+")' % query,
          local topPod(query) = 'label_replace( topk(1, %s) * on(namespace) group_left(label_appcat_vshn_io_claim_namespace) kube_namespace_labels, "name", "$1", "namespace", "vshn-postgresql-(.+)-.+")' % query,
          spec: {
            groups: [
              {
                name: 'postgresql-storage',
                local queries = {
                  availableStorage: 'kubelet_volume_stats_available_bytes{job="kubelet", metrics_path="/metrics"}',
                  availablePercent: '(%s / kubelet_volume_stats_capacity_bytes{job="kubelet", metrics_path="/metrics"})' % queries.availableStorage,
                  usedStorage: 'kubelet_volume_stats_used_bytes{job="kubelet", metrics_path="/metrics"}',
                  unlessExcluded: 'unless on(namespace, persistentvolumeclaim) kube_persistentvolumeclaim_access_mode{ access_mode="ReadOnlyMany"} == 1 unless on(namespace, persistentvolumeclaim) kube_persistentvolumeclaim_labels{label_excluded_from_alerts="true"} == 1',
                },
                rules: [
                  {
                    alert: 'PostgreSQLPersistentVolumeFillingUp',
                    annotations: {
                      description: 'The volume claimed by the instance {{ $labels.name }} in namespace {{ $labels.label_appcat_vshn_io_claim_namespace }} is only {{ $value | humanizePercentage }} free.',
                      runbook_url: 'https://runbooks.prometheus-operator.dev/runbooks/kubernetes/kubepersistentvolumefillingup',
                      summary: 'PersistentVolume is filling up.',
                    },
                    expr: bottomPod('%(availablePercent)s < 0.03 and %(usedStorage)s > 0 %(unlessExcluded)s' % queries),
                    'for': '1m',
                    labels: {
                      severity: 'critical',
                      syn_team: 'schedar',
                    },
                  },
                  {
                    alert: 'PostgreSQLPersistentVolumeFillingUp',
                    annotations: {
                      description: 'Based on recent sampling, the volume claimed by the instance {{ $labels.name }} in namespace {{ $labels.label_appcat_vshn_io_claim_namespace }} is expected to fill up within four days. Currently {{ $value | humanizePercentage }} is available.',
                      runbook_url: 'https://runbooks.prometheus-operator.dev/runbooks/kubernetes/kubepersistentvolumefillingup',
                      summary: 'PersistentVolume is filling up.',
                    },
                    expr: bottomPod('%(availablePercent)s < 0.15 and %(usedStorage)s > 0 and predict_linear(%(availableStorage)s[6h], 4 * 24 * 3600) < 0  %(unlessExcluded)s' % queries),
                    'for': '1h',
                    labels: {
                      severity: 'warning',
                    },
                  },
                ],
              },
              {
                name: 'postgresql-memory',
                rules: [
                  {
                    alert: 'PostgreSQLMemoryCritical',
                    annotations: {
                      description: 'The memory claimed by the instance {{ $labels.name }} in namespace {{ $labels.label_appcat_vshn_io_claim_namespace }} has been over 85% for 2 hours.\n  Please reducde the load of this instance, or increase the memory.',
                      // runbook_url: 'TBD',
                      summary: 'Memory usage critical',
                    },
                    expr: topPod('(container_memory_working_set_bytes{container="patroni"}  / on(container,pod,namespace)  kube_pod_container_resource_limits{resource="memory"} * 100) > 85'),
                    'for': '120m',
                    labels: {
                      severity: 'critical',
                      syn_team: 'schedar',
                    },
                  },
                ],
              },
              {
                name: 'postgresql-connections',
                rules: [
                  {
                    alert: 'PostgreSQLConnectionsCritical',
                    annotations: {
                      description: 'The number of connections to the instance {{ $labels.name }} in namespace {{ $labels.label_appcat_vshn_io_claim_namespace }} have been over 90% of the configured connections for 2 hours.\n  Please reduce the load of this instance.',
                      // runbook_url: 'TBD',
                      summary: 'Connection usage critical',
                    },
                    expr: topPod('sum(pg_stat_activity_count) by (pod, namespace) > 90/100 * sum(pg_settings_max_connections) by (pod, namespace)'),
                    'for': '120m',
                    labels: {
                      severity: 'critical',
                      syn_team: 'schedar',
                    },
                  },
                ],
              },
              // new
              {
                name: 'postgresql-replication',
                rules: [
                  {
                    alert: 'PostgreSQLReplicationCritical',
                    annotations: {
                      description: 'The number of replicas for the instance {{ $labels.cluster_name }} in namespace {{ $labels.namespace }}. Please check pod counts in affected namespace.',
                      runbook_url: 'https://hub.syn.tools/appcat/runbooks/vshn-postgresql.html#PostgreSQLReplicationCritical',
                      summary: 'Replication status check',
                    },
                    expr: 'pg_replication_slots_active == 0',
                    'for': '10m',
                    labels: {
                      severity: 'critical',
                      syn_team: 'schedar',
                    },
                  },
                ],
              },
              {
                name: 'postgresql-replication-lag',
                rules: [
                  {
                    alert: 'PostgreSQLReplicationLagCritical',
                    annotations: {
                      description: 'Replication lag size on namespace {{$labels.exported_namespace}} instance ({{$labels.application_name}}) is currently {{ $value | humanize1024}}B behind the leader.',
                      runbook_url: 'https://hub.syn.tools/appcat/runbooks/vshn-postgresql.html#PostgreSQLReplicationLagCritical',
                      summary: 'Replication lag status check',
                    },
                    expr: 'pg_replication_status_lag_size > 1e+09',
                    'for': '5m',
                    labels: {
                      severity: 'critical',
                      syn_team: 'schedar',
                    },
                  },
                ],
              },
              {
                name: 'postgresql-replication-count',
                rules: [
                  {
                    alert: 'PostgreSQLPodReplicasCritical',
                    annotations: {
                      description: 'Replication is broken in namespace {{$labels.namespace}}, check statefulset ({{$labels.statefulset}}).',
                      runbook_url: 'https://hub.syn.tools/appcat/runbooks/vshn-postgresql.html#PostgreSQLPodReplicasCritical',
                      summary: 'Replication lag status check',
                    },
                    expr: 'kube_statefulset_status_replicas_available{statefulset=~".+", namespace=~"vshn-postgresql-.+"} != kube_statefulset_replicas{statefulset=~".+",namespace=~"vshn-postgresql-.+"}',
                    'for': '5m',
                    labels: {
                      severity: 'critical',
                      syn_team: 'schedar',
                    },
                  },
                ],
              },
            ],
          },
        },
      },
    },
  },
  patches: [
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'prometheusrule'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
  ],
};

local podMonitor = {
  name: 'podmonitor',
  base: comp.KubeObject('monitoring.coreos.com/v1', 'PodMonitor') + {
    spec+: {
      forProvider+: {
        manifest+: {
          metadata: {
            name: 'postgresql-podmonitor',
          },
          spec: {
            podMetricsEndpoints: [
              {
                port: 'pgexporter',
              },
            ],
            selector: {
              matchLabels: {
                app: 'StackGresCluster',
              },
            },
          },
        },
      },
    },
  },
  patches: [
    comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'podmonitor'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', 'vshn-postgresql'),
    comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.selector.matchLabels[stackgres.io/cluster-name]'),
    comp.FromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.spec.namespaceSelector.matchNames[0]', 'vshn-postgresql'),
  ],
};

local composition(restore=false) =

  local metadata = if restore then common.vshnMetaVshnDBaas('PostgreSQLRestore', 'standalone', 'false', pgPlans) else common.vshnMetaVshnDBaas('PostgreSQL', 'standalone', 'true', pgPlans);
  local compositionName = if restore then 'vshnpostgresrestore.vshn.appcat.vshn.io' else 'vshnpostgres.vshn.appcat.vshn.io';
  local copyJobFunction(restore) = if restore then [ copyJob ] else [];

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', compositionName) +
  common.SyncOptions +
  metadata +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: pgParams.secretNamespace,
      functions:
        [
          {
            name: 'pgsql-func',
            type: 'Container',
            config: kube.ConfigMap('xfn-config') + {
              metadata: {
                labels: {
                  name: 'xfn-config',
                },
                name: 'xfn-config',
              },
              data: {
                imageTag: common.GetAppCatImageTag(),
                sgNamespace: pgParams.sgNamespace,
                emailAlertingEnabled: std.toString(params.services.vshn.emailAlerting.enabled),
                emailAlertingSecretNamespace: params.services.vshn.emailAlerting.secretNamespace,
                emailAlertingSecretName: params.services.vshn.emailAlerting.secretName,
                emailAlertingSmtpFromAddress: params.services.vshn.emailAlerting.smtpFromAddress,
                emailAlertingSmtpUsername: params.services.vshn.emailAlerting.smtpUsername,
                emailAlertingSmtpHost: params.services.vshn.emailAlerting.smtpHost,
                externalDatabaseConnectionsEnabled: std.toString(params.services.vshn.externalDatabaseConnectionsEnabled),
                quotasEnabled: std.toString(params.services.vshn.quotasEnabled),
                sideCars: std.toString(pgParams.sideCars),
              },
            },
            container: {
              image: 'postgresql',
              imagePullPolicy: 'IfNotPresent',
              timeout: '20s',
              runner: {
                endpoint: pgParams.grpcEndpoint,
              },
            },
          },
        ],
      resources: [
                   claimNamespaceObserve,
                   instanceNamespace,
                   comp.NamespacePermissions('vshn-postgresql'),
                   localca,
                   certificate,
                 ] +
                 copyJobFunction(restore) +
                 [
                   sgInstanceProfile,
                   sgPostgresConfig,
                   sgCluster +
                   if restore then clusterRestoreConfig else {},
                   secret,
                   xobjectBucket,
                   sgObjectStorage,
                   podMonitor,
                   prometheusRule,
                 ] + if pgParams.enableNetworkPolicy == true then [
        networkPolicy,
      ] else [],
    },
  };

local defaultComp = composition();
local restoreComp = composition(true);

// OpenShift template configuration
local templateObject = kube._Object('vshn.appcat.vshn.io/v1', 'VSHNPostgreSQL', '${INSTANCE_NAME}') + {
  spec: {
    parameters: {
      service: {
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

local templateDescription = 'PostgreSQL is a powerful, open source object-relational database system that uses and extends the SQL language combined with many features that safely store and scale the most complicated data workloads. The origins of PostgreSQL date back to 1986 as part of the POSTGRES project at the University of California at Berkeley and has more than 30 years of active development on the core platform.';
local templateMessage = 'Your PostgreSQL by VSHN instance is being provisioned, please see ${SECRET_NAME} for access.';

local osTemplate =
  common.OpenShiftTemplate('postgresqlbyvshn',
                           'PostgreSQL',
                           templateDescription,
                           'icon-postgresql',
                           'database,sql,postgresql',
                           templateMessage,
                           'VSHN',
                           'https://vs.hn/vshn-postgresql') + {
    objects: [
      templateObject,
    ],
    parameters: [
      {
        name: 'PLAN',
        value: 'standard-4',
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
        value: '15',
      },
    ],
  };

local plansCM = kube.ConfigMap('vshnpostgresqlplans') + {
  metadata+: {
    namespace: params.namespace,
  },
  data: {
    plans: std.toString(pgPlans),
    sideCars: std.toString(pgParams.sideCars),
  },
};

if params.services.vshn.enabled && pgParams.enabled then
  assert std.length(pgParams.bucket_region) != 0 : 'appcat.services.vshn.postgres.bucket_region is empty';
  assert std.length(pgParams.bucket_endpoint) != 0 : 'appcat.services.vshn.postgres.bucket_endpoint is empty';
  {
    '20_xrd_vshn_postgres': xrd,
    '20_rbac_vshn_postgres': xrds.CompositeClusterRoles(xrd),
    '20_role_vshn_postgresrestore': [ restoreRole, restoreServiceAccount, restoreClusterRoleBinding ],
    '20_plans_vshn_postgresql': plansCM,
    '21_composition_vshn_postgres': defaultComp,
    '21_composition_vshn_postgresrestore': restoreComp,
    '22_prom_rule_sla_postgres': promRulePostgresSLA,
    [if isOpenshift then '21_openshift_template_postgresql_vshn']: osTemplate,
  } else {}
