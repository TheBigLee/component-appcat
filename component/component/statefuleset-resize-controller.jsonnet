local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local com = import 'lib/commodore.libjsonnet';
local params = inv.parameters.appcat;
local srcImage = params.images.statefulSetResizer;
local imageTag = std.strReplace(srcImage.tag, '/', '_');
local image = srcImage.registry + '/' + srcImage.repository + ':' + imageTag;
local stsParams = params.stsResizer;

local loadManifest(manifest) =
  std.parseJson(kap.yaml_load(inv.parameters._base_directory + '/dependencies/appcat/manifests/statefulset-resize-controller/' + srcImage.tag + '/' + manifest));

local metadata(name) = {
  name: name,
  namespace: params.namespace,
};

local args = [
  '--inplace',
];

local saName = 'sts-resizer';
local roleName = 'appcat:contoller:sts-resizer';
local role = loadManifest('config/rbac/role.yaml') + {
  metadata+: metadata(roleName),
};
local sa = loadManifest('config/rbac/service_account.yaml') + {
  metadata+: metadata(saName),
};

local binding = loadManifest('config/rbac/role_binding.yaml') + {
  metadata+: metadata(roleName),
  roleRef+: {
    name: roleName,
  },
  subjects: [
    {
      name: saName,
      namespace: params.namespace,
      kind: 'ServiceAccount',
    },
  ],
};

local deployment = loadManifest('config/manager/manager.yaml') + {
  metadata+: metadata('sts-resizer'),
  spec+: {
    template+: {
      spec+: {
        serviceAccountName: saName,
        containers: [
          if c.name == 'manager' then
            c {
              image: image,
              args: args,
              resources+: stsParams.resources,
            }
          else
            c
          for c in super.containers
        ],
      },
    },
  },
};

// Curently we only need this for redis.
if params.services.vshn.enabled && params.services.vshn.redis.enabled then {
  'controllers/sts-resizer/10_role': role,
  'controllers/sts-resizer/10_sa': sa,
  'controllers/sts-resizer/10_binding': binding,
  'controllers/sts-resizer/10_deployment': deployment,
}
