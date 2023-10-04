// main template for appcat
local compositionHelpers = import 'lib/appcat-compositions.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';


local common = import 'common.libsonnet';


local compositeClusterRoles(composite) =
  if std.get(composite, 'createDefaultRBACRoles', true) then
    [
      kube.ClusterRole('appcat:composite:%s:claim-view' % composite.metadata.name)
      {
        metadata+: {
          labels: {
            'rbac.authorization.k8s.io/aggregate-to-view': 'true',
          },
        },
        rules+: [
          {
            apiGroups: [ composite.spec.group ],
            resources: [
              composite.spec.claimNames.plural,
              '%s/status' % composite.spec.claimNames.plural,
              '%s/finalizers' % composite.spec.claimNames.plural,
            ],
            verbs: [ 'get', 'list', 'watch' ],
          },
        ],
      },
      kube.ClusterRole('appcat:composite:%s:claim-edit' % composite.metadata.name)
      {
        metadata+: {
          labels: {
            'rbac.authorization.k8s.io/aggregate-to-edit': 'true',
            'rbac.authorization.k8s.io/aggregate-to-admin': 'true',
          },
        },
        rules+: [
          {
            apiGroups: [ composite.spec.group ],
            resources: [
              composite.spec.claimNames.plural,
              '%s/status' % composite.spec.claimNames.plural,
              '%s/finalizers' % composite.spec.claimNames.plural,
            ],
            verbs: [ '*' ],
          },
        ],
      },
    ];


local loadCRD(crd, tag) = std.parseJson(kap.yaml_load('appcat/manifests/' + tag + '/crds/' + crd));

local xrdFromCRD(name, crd, defaultComposition='', connectionSecretKeys=[]) =
  kube._Object('apiextensions.crossplane.io/v1', 'CompositeResourceDefinition', name) + common.SyncOptions + {
    spec: {
      claimNames: {
        kind: crd.spec.names.kind,
        plural: crd.spec.names.plural,
      },
      names: {
        kind: 'X%s' % crd.spec.names.kind,
        plural: 'x%s' % crd.spec.names.plural,
      },
      connectionSecretKeys: connectionSecretKeys,
      [if defaultComposition != '' then 'defaultCompositionRef']: {
        name: defaultComposition,
      },
      group: crd.spec.group,
      versions: [ v {
        schema+: {
          openAPIV3Schema+: {
            properties+: {
              metadata:: {},
              kind:: {},
              apiVersion:: {},
              spec+: {
                properties: {
                  parameters: v.schema.openAPIV3Schema.properties.spec.properties.parameters,
                },
              },
            },
          },
        },
        referenceable: true,
        storage:: '',
        subresources:: [],
      } for v in crd.spec.versions ],
    },
  };

local withPlanDefaults(plans, defaultPlan) = {
  spec+: {
    versions: [
      v {
        schema+: {
          openAPIV3Schema+: {
            properties+: {
              spec+: {
                properties+: {
                  parameters+: {
                    properties+: {
                      size+: {
                        properties+: {
                          plan+: {
                            default: defaultPlan,
                            enum: std.objectFields(plans),

                            description: |||
                              %s

                              The following plans are available:

                                %s
                            ||| % [
                              super.description,
                              std.join(
                                '\n\n  ',
                                [
                                  '%s - CPU: %s; Memory: %s; Disk: %s' % [ p, plans[p].size.cpu, plans[p].size.memory, plans[p].size.disk ]
                                  + if std.objectHas(plans[p], 'note') && plans[p].note != '' then ' - %s' % plans[p].note else ''

                                  for p in std.objectFields(plans)
                                ]
                              ),
                            ],
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      }
      for v in super.versions
    ],
  },
};


{
  CompositeClusterRoles(composite):
    compositeClusterRoles(composite),
  LoadCRD(crd, tag):
    loadCRD(crd, tag),
  XRDFromCRD(name, crd, defaultComposition='', connectionSecretKeys=[]):
    xrdFromCRD(name, crd, defaultComposition=defaultComposition, connectionSecretKeys=connectionSecretKeys),
  WithPlanDefaults(plans, defaultPlan):
    withPlanDefaults(plans, defaultPlan),
}
