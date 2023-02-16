local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local rbac = import 'rbac.libsonnet';

local inv = kap.inventory();
local facts = inv.parameters.facts;
local params = inv.parameters.appcat;

local exoscaleZones = [ 'de-fra-1', 'de-muc-1', 'at-vie-1', 'ch-gva-2', 'ch-dk-2', 'bg-sof-1' ];
local cloudscaleZones = [ 'lpg', 'rma' ];

local strExoscaleZones = std.join(', ', exoscaleZones);
local strCloudscaleZones = std.join('and', cloudscaleZones);

local syncOptions = {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
      'argocd.argoproj.io/sync-wave': '10',
    },
  },
};

local vshnMetaDBaaSExoscale(dbname) = {
  metadata+: {
    annotations+: {
      'metadata.appcat.vshn.io/displayname': 'Exoscale ' + dbname,
      'metadata.appcat.vshn.io/description': dbname + ' DBaaS instances by Exoscale',
      'metadata.appcat.vshn.io/end-user-docs-url': 'https://docs.appuio.cloud/appcat/exoscale-dbaas/' + std.asciiLower(dbname) + '/create.html',
      'metadata.appcat.vshn.io/zone': 'Exoscale zones: ' + strExoscaleZones,
      'metadata.appcat.vshn.io/product-description': 'https://products.docs.vshn.ch/products/appcat/exoscale_dbaas.html',
    },
    labels+: {
      'metadata.appcat.vshn.io/offered': 'true',
      'metadata.appcat.vshn.io/serviceID': 'exoscale-' + std.asciiLower(dbname),
    },
  },
};

local vshnMetaVshn(dbname, flavor, offered) = {
  metadata+: {
    annotations+: {
      'metadata.appcat.vshn.io/displayname': 'VSHN Managed ' + dbname,
      'metadata.appcat.vshn.io/description': dbname + ' instances by VSHN',
      'metadata.appcat.vshn.io/end-user-docs-url': 'https://docs.appuio.cloud/appcat/vshn-dbaas/' + std.asciiLower(dbname) + '/create.html',
      'metadata.appcat.vshn.io/zone': facts.region,
      'metadata.appcat.vshn.io/flavor': flavor,
      'metadata.appcat.vshn.io/product-description': 'https://products.docs.vshn.ch/products/appcat/' + std.asciiLower(dbname) + '.html',
    },
    labels+: {
      'metadata.appcat.vshn.io/offered': offered,
      'metadata.appcat.vshn.io/serviceID': 'vshn-' + std.asciiLower(dbname),
    },
  },
};

local vshnMetaObjectStorage(provider) = {
  metadata+: {
    annotations+: {
      'metadata.appcat.vshn.io/displayname': provider + ' Object Storage',
      'metadata.appcat.vshn.io/description': 'S3 compatible object storage hosted by ' + provider,
      'metadata.appcat.vshn.io/end-user-docs-url': 'https://docs.appuio.cloud/appcat/object-storage/create.html',
      'metadata.appcat.vshn.io/zone': provider + ' zones: ' +
                                      if provider == 'Exoscale' then strExoscaleZones else strCloudscaleZones,
      'metadata.appcat.vshn.io/product-description': 'https://products.docs.vshn.ch/products/appcat/objectstorage.html',
    },
    labels+: {
      'metadata.appcat.vshn.io/offered': 'true',
      'metadata.appcat.vshn.io/serviceID': std.asciiLower(std.rstripChars(provider, '.ch')) + '-objectbucket',
    },
  },
};

local mergeArgs(args, additional) =
  local foldFn =
    function(acc, arg)
      local ap = std.splitLimit(arg, '=', 1);
      acc { [ap[0]]: ap[1] };
  local base = std.foldl(foldFn, args, {});
  local final = std.foldl(foldFn, additional, base);
  [ '%s=%s' % [ k, final[k] ] for k in std.objectFields(final) ];


{
  SyncOptions: syncOptions,
  VshnMetaDBaaSExoscale(dbname):
    vshnMetaDBaaSExoscale(dbname),
  VshnMetaObjectStorage(provider):
    vshnMetaObjectStorage(provider),
  MergeArgs(args, additional):
    mergeArgs(args, additional),
  VshnMetaVshn(dbname, flavor, offered='true'):
    vshnMetaVshn(dbname, flavor, offered),
}
