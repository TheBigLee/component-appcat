local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.appcat;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('appcat', '');

{
  appcat: app,
}
