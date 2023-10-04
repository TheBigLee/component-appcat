local common = import 'common.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appcat;
local sli_exporter_params = params.slos.sli_exporter;

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');

local deployment_patch = kube._Object('apps/v1', 'Deployment', 'controller-manager') {
  metadata+: {
    namespace: 'system',
  },
  spec+: {
    template: {
      spec: {
        containers: [
          {
            name: 'manager',
            resources: sli_exporter_params.resources,
            env: [
              {
                name: 'APPCAT_SLI_VSHNPOSTGRESQL',
                value: std.manifestJson(params.services.vshn.enabled && params.services.vshn.postgres.enabled),
              },
              {
                name: 'APPCAT_SLI_VSHNREDIS',
                value: std.manifestJson(params.services.vshn.enabled && params.services.vshn.redis.enabled),
              },
            ],
          },
        ],
      },
    },
  },
};

local namespace_patch = kube.Namespace('system') {
  metadata+: {
    labels: {
      [if isOpenshift then 'openshift.io/cluster-monitoring']: 'true',  // Enable cluster-monitoring on APPUiO Managed OpenShift
    } + params.slos.namespaceLabels,
    annotations+: params.slos.namespaceAnnotations,
  },
};


local kustomization =
  if params.slos.enabled then
    local image = params.images.appcat;
    com.Kustomization(
      'https://github.com/vshn/appcat/config/sliexporter/default',
      image.tag,
      {
        'ghcr.io/vshn/appcat': {
          newTag: common.GetAppCatImageTag(),
          newName: '%(registry)s/%(repository)s' % image,
        },
      },
      sli_exporter_params.kustomize_input,
    ) {
      kustomization+: {
        patchesStrategicMerge: [
          'deployment_patch.yaml',
          'namespace_patch.yaml',
        ],
      },
      deployment_patch: deployment_patch,
      namespace_patch: namespace_patch,
    }
  else {
    kustomization: { resources: [] },
  };


kustomization
