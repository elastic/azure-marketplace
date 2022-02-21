@description('Set up an internal or external load balancer, or use Application Gateway (gateway) for load balancing and SSL offload. If you are setting up Elasticsearch on a publicly available endpoint, it is *strongly recommended* to secure your nodes with a product like the Elastic Stack\'s Security features')
@allowed([
  'internal'
  'external'
  'gateway'
])
param loadBalancerType string = 'internal'

@description('The tier of the Application Gateway. Required when selecting Application Gateway for load balancing')
@allowed([
  'Standard'
  'WAF'
])
param appGatewayTier string = 'Standard'

param applicationGatewaySettings object
param networkSettings object
param elasticTags object

var loadBalancer = loadBalancerType == 'gateway' ? '${toLower(appGatewayTier)}-gateway' : loadBalancerType

module internalLoadBalancer './internal-lb-resources.bicep' = if (loadBalancer == 'internal') {
  name: 'internal-load-balancer'
  params: {
    networkSettings: networkSettings
    elasticTags: elasticTags
  }
}

module externalLoadBalancer './external-lb-resources.bicep' = if (loadBalancer == 'external' ) {
  name: 'external-load-balancer'
  params: {
    networkSettings: networkSettings
    elasticTags: elasticTags
  }
}

module standardAppGwLoadBalancer './standard-application-gateway-resources.bicep' = if (loadBalancer == 'standard-gateway') {
  name: 'standard-appgw-load-balancer'
  params: {
    networkSettings: networkSettings
    applicationGatewaySettings: applicationGatewaySettings
    elasticTags: elasticTags
  }
}

module wafAppGwLoadBalancer './waf-application-gateway-resources.bicep' = if (loadBalancer == 'waf-gateway') {
  name: 'waf-appgw-load-balancer'
  params: {
    networkSettings: networkSettings
    applicationGatewaySettings: applicationGatewaySettings
    elasticTags: elasticTags
  }
}

output fqdn string = loadBalancer == 'internal' ? internalLoadBalancer.outputs.fqdn : loadBalancer == 'external' ? externalLoadBalancer.outputs.fqdn : loadBalancer == 'standard-gateway' ? standardAppGwLoadBalancer.outputs.fqdn : wafAppGwLoadBalancer.outputs.fqdn
