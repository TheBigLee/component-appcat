local fromCompositeFieldPath(from, to) = {
  // this is the default patch type
  // This type patches from a field within the XR to a field within the composed resource.
  // It’s commonly used to expose a composed resource spec field as an XR spec field.
  type: 'FromCompositeFieldPath',
  fromFieldPath: from,
  toFieldPath: to,
};


local fromCompositeFieldPathWithTransform(from, to, prefix, suffix) = fromCompositeFieldPath(from, to) + {
  // this is an enhanced patch type with a transform function that adds the 3rd argument as a suffix
  transforms: [
    {
      type: 'string',
      string: {
        fmt: prefix + '%s' + suffix,
        type: 'Format',
      },
    },
  ],
};

local fromCompositeFieldPathWithTransformSuffix(from, to, suffix) = fromCompositeFieldPath(from, to) + {
  // this is an enhanced patch type with a transform function that adds the 3rd argument as a suffix
  transforms: [
    {
      type: 'string',
      string: {
        fmt: '%s-' + suffix,
        type: 'Format',
      },
    },
  ],
};

local fromCompositeFieldPathWithTransformPrefix(from, to, prefix) = fromCompositeFieldPath(from, to) + {
  // this is an enhanced patch type with a transform function that adds the 3rd argument as a prefix
  transforms: [
    {
      type: 'string',
      string: {
        fmt: prefix + '-%s',
        type: 'Format',
      },
    },
  ],
};

local fromCompositeFieldPathWithTransformMap(from, to, map) = fromCompositeFieldPath(from, to) + {
  // this is an enhanced patch type with a transform function that maps values given the provided object
  transforms: [
    {
      type: 'map',
      map: map,
    },
  ],
};

local fromCompositeFieldPathWithTransformMatch(from, to, patterns) = fromCompositeFieldPath(from, to) + {
  // this is an enhanced patch type with a transform function that matches values given the provided object
  transforms: [
    {
      type: 'match',
      match: {
        patterns: patterns,
      },
    },
  ],
};

local combineCompositeFromOneFieldPath(fromOne, to, format) = {
  // this is the default combine patch type
  // This type patches from a field within the XR to a field within the composed resource using format function.
  type: 'CombineFromComposite',
  toFieldPath: to,
  combine: {
    variables: [
      {
        fromFieldPath: fromOne,
      },
    ],
    strategy: 'string',
    string: {
      fmt: format,
    },
  },
};

local combineCompositeFromTwoFieldPaths(fromOne, fromTwo, to, format) = {
  // this is the default combine patch type
  // This type patches from a two field within the XR to a field within the composed resource using format function.
  type: 'CombineFromComposite',
  toFieldPath: to,
  combine: {
    variables: [
      {
        fromFieldPath: fromOne,
      },
      {
        fromFieldPath: fromTwo,
      },
    ],
    strategy: 'string',
    string: {
      fmt: format,
    },
  },
};

local toCompositeFieldPath(from, to) = {
  //  This type patches from a field within the composed resource to a field within the XR.
  // It’s commonly used to derive an XR status field from a composed resource status field.
  type: 'ToCompositeFieldPath',
  fromFieldPath: from,
  toFieldPath: to,
};

local commonResources = {
  observeClaimNamespace: {
    // This resource "observes" the namespace of the Claim.
    // It can be used to copy labels and annotations from the namespace to the composition.
    // Requirements: provider-kubernetes (https://github.com/crossplane-contrib/provider-kubernetes)
    base: {
      apiVersion: 'kubernetes.crossplane.io/v1alpha1',
      kind: 'Object',
      spec: {
        managementPolicy: 'Observe',
        forProvider: {
          manifest: {
            apiVersion: 'v1',
            kind: 'Namespace',
            metadata: {
              name: '',  // patched at runtime
            },
          },
        },
        providerConfigRef: {
          name: 'kubernetes',
        },
      },
    },
    patches: [
      fromCompositeFieldPath(from='metadata.labels[crossplane.io/claim-namespace]', to='spec.forProvider.manifest.metadata.name'),
      toCompositeFieldPath(from='status.atProvider.manifest.metadata.labels[appuio.io/organization]', to='metadata.labels[appuio.io/organization]'),
      fromCompositeFieldPath(from='metadata.labels[crossplane.io/composite]', to='metadata.name') + {
        transforms: [ {
          type: 'string',
          string: { fmt: '%s-ns-observer', type: 'Format' },
        } ],
      },
    ],

  },
};


local compositeRef(xrd, version='') = {
  apiVersion: '%s/%s' % [
    xrd.spec.group,
    if version == '' then xrd.spec.versions[0].name else version,
  ],
  kind: xrd.spec.names.kind,
};

local connFromSecretKey(name, from=name) = {
  name: name,
  fromConnectionSecretKey: from,
  type: 'FromConnectionSecretKey',
};
local connFromFieldPath(name, field) = {
  fromFieldPath: field,
  type: 'FromFieldPath',
  name: name,
};

local kubeObject(apiVersion, kind) = {
  apiVersion: 'kubernetes.crossplane.io/v1alpha1',
  kind: 'Object',
  metadata: {},
  spec: {
    providerConfigRef: {
      name: 'kubernetes',
    },
    forProvider: {
      manifest: {
        apiVersion: apiVersion,
        kind: kind,
      },
    },
  },
};

local namespacePermissions(namespacePrefix) = {
  name: 'namespace-permissions',
  base: {
    apiVersion: 'kubernetes.crossplane.io/v1alpha1',
    kind: 'Object',
    spec: {
      providerConfigRef: {
        name: 'kubernetes',
      },
      forProvider: {
        manifest: {
          apiVersion: 'rbac.authorization.k8s.io/v1',
          kind: 'RoleBinding',
          metadata: {
            name: 'appcat:services:read',
          },
          roleRef: {
            apiGroup: 'rbac.authorization.k8s.io',
            kind: 'ClusterRole',
            name: 'appcat:services:read',
          },
          subjects: [
            {
              apiGroup: 'rbac.authorization.k8s.io',
              kind: 'Group',
              // This name will be patched on APPUiO, on kind the labels don't exist
              // so we use some dummy value.
              name: 'organization',
            },
          ],
        },
      },
    },
  },
  patches: [
    fromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'service-rolebinding'),
    fromCompositeFieldPath(from='metadata.labels[appuio.io/organization]', to='spec.forProvider.manifest.subjects[0].name'),
    fromCompositeFieldPathWithTransformPrefix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.manifest.metadata.namespace', namespacePrefix),
  ],
};

{
  CommonResource(name):
    assert std.objectHas(commonResources, name) : "common resources set '%s' doesn't exist" % name;
    commonResources[name],
  FromCompositeFieldPath(from, to):
    fromCompositeFieldPath(from, to),
  FromCompositeFieldPathWithTransformMap(from, to, map):
    fromCompositeFieldPathWithTransformMap(from, to, map),
  FromCompositeFieldPathWithTransformMatch(from, to, pattern):
    fromCompositeFieldPathWithTransformMatch(from, to, pattern),
  FromCompositeFieldPathWithTransformSuffix(from, to, suffix):
    fromCompositeFieldPathWithTransformSuffix(from, to, suffix),
  FromCompositeFieldPathWithTransformPrefix(from, to, prefix):
    fromCompositeFieldPathWithTransformPrefix(from, to, prefix),
  CombineCompositeFromOneFieldPath(fromOne, to, format):
    combineCompositeFromOneFieldPath(fromOne, to, format),
  CombineCompositeFromTwoFieldPaths(fromOne, fromTwo, to, format):
    combineCompositeFromTwoFieldPaths(fromOne, fromTwo, to, format),
  FromCompositeFieldPathWithTransform(from, to, prefix, suffix):
    fromCompositeFieldPathWithTransform(from, to, prefix, suffix),
  ToCompositeFieldPath(from, to):
    toCompositeFieldPath(from, to),
  CompositeRef(xrd, version=''):
    compositeRef(xrd, version=version),
  KubeObject(apiVersion, kind):
    kubeObject(apiVersion, kind),
  NamespacePermissions(namespacePrefix):
    namespacePermissions(namespacePrefix),
  conn: {
    FromSecretKey(name, from=name):
      connFromSecretKey(name, from=name),
    AllFromSecretKeys(keys):
      [ connFromSecretKey(key, from=key) for key in keys ],
    FromFieldPath(name, field):
      connFromFieldPath(name, field),
  },
}
