// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local slos = import 'slos.libsonnet';


local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appcat;


std.mapWithKey(function(name, obj) {
  version: 'prometheus/v1',
  service: 'appcat-' + name,
  slos: obj,
}, slos.slothInput)
