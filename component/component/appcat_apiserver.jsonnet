local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local com = import 'lib/commodore.libjsonnet';
local params = inv.parameters.appcat;
local apiserverParams = params.apiserver;

local image = params.images.apiserver;
local loadManifest(manifest) =
  std.parseJson(kap.yaml_load(inv.parameters._base_directory + '/dependencies/appcat-apiserver/manifests/' + image.tag + '/config/apiserver/' + manifest));

local envs = loadManifest('apiserver-envs.yaml') {
  data+: apiserverParams.env,
  metadata+: {
    namespace: apiserverParams.namespace,
  },
};

local clusterRoleUsers = kube.ClusterRole('system:' + inv.parameters.facts.distribution + ':aggregate-appcat-to-basic-user') {
  metadata+: {
    labels+: {
      'authorization.openshift.io/aggregate-to-basic-user': 'true',
    },
  },
  rules+: [
    {
      apiGroups: [ 'api.appcat.vshn.io' ],
      resources: [ 'appcats' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};

local clusterRoleView = kube.ClusterRole('appcat:api:view') {
  metadata+: {
    labels+: {
      'rbac.authorization.k8s.io/aggregate-to-view': 'true',
    },
  },
  rules+: [
    {
      apiGroups: [ 'api.appcat.vshn.io' ],
      resources: [ 'vshnpostgresbackups', 'vshnredisbackups' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};


local serviceAccount = loadManifest('service-account.yaml') {
  metadata+: {
    namespace: apiserverParams.namespace,
  },
};

local clusterRoleAPIServer = loadManifest('role.yaml');

local clusterRoleBinding = kube.ClusterRoleBinding(clusterRoleAPIServer.metadata.name) {
  roleRef: {
    kind: 'ClusterRole',
    apiGroup: 'rbac.authorization.k8s.io',
    name: clusterRoleAPIServer.metadata.name,
  },
  subjects: [
    {
      kind: 'ServiceAccount',
      name: serviceAccount.metadata.name,
      namespace: serviceAccount.metadata.namespace,
    },
  ],
};

local extraDeploymentArgs =
  if apiserverParams.tls.certSecretName != null then
    [
      '--tls-cert-file=/apiserver.local.config/certificates/tls.crt',
      '--tls-private-key-file=/apiserver.local.config/certificates/tls.key',
    ] else null;

local apiserver = loadManifest('aggregated-apiserver.yaml') {
  metadata+: {
    namespace: apiserverParams.namespace,
  },
  spec+: {
    template+: {
      spec+: {
        containers: [
          if c.name == 'apiserver' then
            c {
              image: common.GetApiserverImageString(),
              args: [ super.args[0] ] + common.MergeArgs(common.MergeArgs(super.args[1:], extraDeploymentArgs), apiserverParams.extraArgs),
              env+: com.envList(apiserverParams.extraEnv),
              resources: apiserverParams.resources,
            }
          else
            c
          for c in super.containers
        ],
      } + if apiserverParams.tls.certSecretName != null then
        {
          volumes: [
            {
              name: 'apiserver-certs',
              secret: {
                secretName: apiserverParams.tls.certSecretName,
              },
            },
          ],
        } else {},
    },
  },
};

local service = loadManifest('service.yaml') {
  metadata+: {
    namespace: apiserverParams.namespace,
  },
};


local apiService = loadManifest('apiservice.yaml') {
  metadata+: {
    annotations: {
      'cert-manager.io/inject-ca-from': apiserverParams.namespace + '/apiserver-certificate',
    },
  },
  spec+:
    {
      service: {
        name: service.metadata.name,
        namespace: service.metadata.namespace,
      },
    }
    +
    apiserverParams.apiservice
    +
    (
      if apiserverParams.apiservice.insecureSkipTLSVerify == false
      then
        {
          insecureSkipTLSVerify:: null,
        }
      else {}
    ),
};

local apiIssuer = {
  apiVersion: 'cert-manager.io/v1',
  kind: 'Issuer',
  metadata: {
    name: 'api-server-issuer',
    namespace: apiserverParams.namespace,
  },
  spec: {
    selfSigned: {},
  },
};

local apiCertificate = {
  apiVersion: 'cert-manager.io/v1',
  kind: 'Certificate',
  metadata: {
    name: 'apiserver-certificate',
    namespace: apiserverParams.namespace,
  },
  spec: {
    dnsNames: [ service.metadata.name + '.' + apiserverParams.namespace + '.svc' ],
    duration: '87600h0m0s',
    issuerRef: {
      group: 'cert-manager.io',
      kind: 'Issuer',
      name: apiIssuer.metadata.name,
    },
    privateKey: {
      algorithm: 'RSA',
      encoding: 'PKCS1',
      size: 4096,
    },
    renewBefore: '2400h0m0s',
    secretName: apiserverParams.tls.certSecretName,
    subject: {
      organizations: [ 'vshn-appcat' ],
    },
    usages: [
      'server auth',
      'client auth',
    ],
  },
};

if apiserverParams.enabled == true then {
  'apiserver/10_cluster_role_api_server': clusterRoleAPIServer,
  'apiserver/10_cluster_role_basic_users': clusterRoleUsers,
  'apiserver/10_cluster_role_view': clusterRoleView,
  'apiserver/10_cluster_role_binding': clusterRoleBinding,
  'apiserver/20_service_account': serviceAccount,
  'apiserver/10_apiserver_envs': envs,
  'apiserver/30_deployment': apiserver,
  'apiserver/30_service': service,
  'apiserver/30_api_service': apiService,
  [if apiserverParams.tls.certSecretName != null then 'apiserver/31_api_issuer']: apiIssuer,
  [if apiserverParams.tls.certSecretName != null then 'apiserver/31_api_certificate']: apiCertificate,
} else {}
