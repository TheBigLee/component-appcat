local common = import 'common.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local crossplane = import 'lib/crossplane.libsonnet';


local inv = kap.inventory();
local params = inv.parameters.appcat;

local addCredentials(config, credentials) = config {
  credentials: std.get(config, 'credentials', default=credentials),
};

local providerSecret(credentials) =
  kube.Secret(credentials.name) {
    metadata+: {
      namespace: credentials.namespace,
    },
    stringData: credentials.data,
  };


local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');
local openshiftControllerConfig =
  (if isOpenshift then {
     podSecurityContext: {},
     securityContext: {},
   }
   else {});


local controllerConfig(name, config) =
  local spec = config + openshiftControllerConfig;
  if spec != {} then
    [
      crossplane.ControllerConfig(name) {
        spec+: spec,
      },
    ]
  else [];

local controllerConfigRef(config) =
  if config != [] then
    {
      controllerConfigRef: {
        name: config[0].metadata.name,
      },
    }
  else {};

{
  [if params.providers.cloudscale.enabled then '10_provider_cloudscale']:
    local provider = params.providers.cloudscale;

    local controllerConf = controllerConfig('cloudscale', provider.controllerConfig);
    [
      crossplane.Provider('cloudscale') {
        spec+: provider.spec + controllerConfigRef(controllerConf),
      },
      crossplane.ProviderConfig('cloudscale') {
        apiVersion: 'cloudscale.crossplane.io/v1',
        spec+: addCredentials(
          provider.providerConfig,
          {
            source: 'InjectedIdentity',
            apiTokenSecretRef: {
              name: provider.credentials.name,
              namespace: provider.credentials.namespace,
            },
          }
        ),
      },
    ]
    +
    controllerConf
    +
    [
      providerSecret(provider.credentials),
      kube.Namespace(provider.connectionSecretNamespace),
    ],
  [if params.providers.exoscale.enabled then '10_provider_exoscale']:
    local provider = params.providers.exoscale;

    local controllerConf = controllerConfig('exoscale', provider.controllerConfig);
    [
      crossplane.Provider('exoscale') {
        spec+: provider.spec + controllerConfigRef(controllerConf),
      },
      crossplane.ProviderConfig('exoscale') {
        apiVersion: 'exoscale.crossplane.io/v1',
        spec+: addCredentials(
          provider.providerConfig,
          {
            source: 'InjectedIdentity',
            apiSecretRef: {
              name: provider.credentials.name,
              namespace: provider.credentials.namespace,
            },
          }
        ),
      },
    ]
    +
    controllerConf
    +
    [
      providerSecret(provider.credentials),
      kube.Namespace(provider.connectionSecretNamespace),
    ],
  [if params.providers.kubernetes.enabled then '10_provider_kubernetes']:
    local provider = params.providers.kubernetes;

    local sa = kube.ServiceAccount(provider.controllerConfig.serviceAccountName) {
      metadata+: {
        namespace: provider.namespace,
      },
    };
    local role = kube.ClusterRole('crossplane:provider:provider-kubernetes:system:custom') {
      rules: [
        {
          apiGroups: [ 'kubernetes.crossplane.io' ],
          resources: [ '*' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ 'helm.crossplane.io' ],
          resources: [ 'releases' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ '', 'coordination.k8s.io' ],
          resources: [ 'secrets', 'configmaps', 'events', 'leases' ],
          verbs: [ '*' ],
        },
        {
          apiGroups: [ '' ],
          resources: [ 'namespaces', 'serviceaccounts', 'secrets', 'pods', 'pods/log', 'pods/portforward', 'pods/status', 'services' ],
          verbs: [ 'get', 'list', 'watch', 'create', 'watch', 'patch', 'update', 'delete' ],
        },
        {
          apiGroups: [ 'apps' ],
          resources: [ 'statefulsets/scale' ],
          verbs: [ 'update', 'patch' ],
        },
        {
          apiGroups: [ 'apps' ],
          resources: [ 'statefulsets' ],
          verbs: [ 'get', 'delete', 'watch', 'list' ],
        },
        {
          apiGroups: [ 'rbac.authorization.k8s.io' ],
          resources: [ 'clusterroles' ],
          resourceNames: [ 'appcat:services:read' ],
          verbs: [ 'bind' ],
        },
        {
          apiGroups: [ 'stackgres.io' ],
          resources: [ 'sginstanceprofiles', 'sgclusters', 'sgpgconfigs', 'sgobjectstorages', 'sgbackups', 'sgdbops' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ 'networking.k8s.io' ],
          resources: [ 'networkpolicies' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ 'appcat.vshn.io' ],
          resources: [ 'xobjectbuckets' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ 'cert-manager.io' ],
          resources: [ 'issuers', 'certificates' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ 'batch' ],
          resources: [ 'jobs', 'cronjobs' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ 'rbac.authorization.k8s.io' ],
          resources: [ 'clusterrolebindings', 'roles', 'rolebindings' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ 'vshn.appcat.vshn.io' ],
          resources: [ 'vshnpostgresqls' ],
          verbs: [ 'get', 'update' ],
        },
        {
          apiGroups: [ 'vshn.appcat.vshn.io' ],
          resources: [ 'vshnredis' ],
          verbs: [ 'get', 'update' ],
        },
        {
          apiGroups: [ 'monitoring.coreos.com' ],
          resources: [ 'prometheusrules', 'podmonitors', 'alertmanagerconfigs' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ 'k8up.io' ],
          resources: [ 'schedules' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ 'k8up.io' ],
          resources: [ 'snapshots' ],
          verbs: [ 'get' ],
        },
        {
          apiGroups: [ 'minio.crossplane.io' ],
          resources: [ 'providerconfigs' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
      ],
    };
    local rolebinding = kube.ClusterRoleBinding('crossplane:provider:provider-kubernetes:system:custom') {
      roleRef_: role,
      subjects_: [ sa ],
    };

    local controllerConf = controllerConfig('kubernetes', provider.controllerConfig);

    [
      crossplane.Provider('kubernetes') {
        spec+: provider.spec + controllerConfigRef(controllerConf),
      },
    ]
    +
    controllerConf
    +
    [

      crossplane.ProviderConfig('kubernetes') {
        apiVersion: 'kubernetes.crossplane.io/v1alpha1',
        spec+: addCredentials(
          provider.providerConfig,
          {
            source: 'InjectedIdentity',
          }
        ),
      },
      sa,
      role,
      rolebinding,
    ],
  [if params.providers.helm.enabled then '10_provider_helm']:
    local provider = params.providers.helm;

    local sa = kube.ServiceAccount(provider.controllerConfig.serviceAccountName) {
      metadata+: {
        namespace: provider.namespace,
      },
    };
    local role = kube.ClusterRole('crossplane:provider:provider-helm:system:custom') {
      rules: [
        {
          apiGroups: [ 'helm.crossplane.io' ],
          resources: [ '*' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ '' ],
          resources: [ 'namespaces', 'serviceaccounts', 'services', 'persistentvolumeclaims' ],
          verbs: [ 'get', 'list', 'watch', 'create', 'watch', 'patch', 'update', 'delete' ],
        },
        {
          apiGroups: [ 'apps' ],
          resources: [ 'statefulsets', 'deployments' ],
          verbs: [ 'get', 'list', 'watch', 'create', 'watch', 'patch', 'update', 'delete' ],
        },
        {
          apiGroups: [ 'networking.k8s.io' ],
          resources: [ 'networkpolicies' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ 'batch' ],
          resources: [ 'jobs' ],
          verbs: [ 'get', 'list', 'watch', 'create', 'delete' ],
        },
      ],
    };
    local rolebinding = kube.ClusterRoleBinding('crossplane:provider:provider-helm:system:custom') {
      roleRef_: role,
      subjects_: [ sa ],
    };


    local controllerConf = controllerConfig('helm', provider.controllerConfig);

    [
      crossplane.Provider('helm') {
        spec+: provider.spec + controllerConfigRef(controllerConf),
      },
    ]
    +
    controllerConf
    +
    [

      crossplane.ProviderConfig('helm') {
        apiVersion: 'helm.crossplane.io/v1beta1',
        spec+: addCredentials(
          provider.providerConfig,
          {
            source: 'InjectedIdentity',
          }
        ),
      },
      sa,
      role,
      rolebinding,
    ],
  [if params.providers.minio.enabled then '10_provider_minio']:
    local provider = params.providers.minio;

    local sa = kube.ServiceAccount(provider.controllerConfig.serviceAccountName) {
      metadata+: {
        namespace: provider.namespace,
      },
    };
    local role = kube.ClusterRole('crossplane:provider:provider-minio:system:custom') {
      rules: [
        {
          apiGroups: [ 'minio.crossplane.io' ],
          resources: [ '*' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
        {
          apiGroups: [ '' ],
          resources: [ 'secrets' ],
          verbs: [ 'get', 'list', 'watch', 'update', 'patch', 'create', 'delete' ],
        },
      ],
    };
    local rolebinding = kube.ClusterRoleBinding('crossplane:provider:provider-minio:system:custom') {
      roleRef_: role,
      subjects_: [ sa ],
    };


    local controllerConf = controllerConfig('minio', provider.controllerConfig);

    [
      crossplane.Provider('minio') {
        spec+: provider.spec + controllerConfigRef(controllerConf),
      },
    ]
    +
    controllerConf
    +
    [
      crossplane.ProviderConfig(config.name) {
        apiVersion: 'minio.crossplane.io/v1',
        spec+: addCredentials(
          common.RemoveField(config, 'name'),
          {
            source: 'InjectedIdentity',
          }
        ),
      }
      for config in provider.additionalProviderConfigs
    ] +
    [
      sa,
      role,
      rolebinding,
    ],
}
