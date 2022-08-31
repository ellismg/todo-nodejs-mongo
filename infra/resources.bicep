param location string
param principalId string = ''
param resourceToken string
param tags object

var abbrs = loadJsonContent('abbreviations.json')

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: '${abbrs.webServerFarms}${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'B1'
  }
  properties: {
    reserved: true
  }
}

resource web 'Microsoft.Web/sites@2022-03-01' = {
  name: '${abbrs.webSitesAppService}web-${resourceToken}'
  location: location
  tags: union(tags, { 'azd-service-name': 'web' })
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'NODE|16-lts'
      alwaysOn: true
      ftpsState: 'FtpsOnly'
      appCommandLine: 'pm2 serve /home/site/wwwroot --no-daemon --spa'
    }
    httpsOnly: true
  }

  resource appSettings 'config' = {
    name: 'appsettings'
    properties: {
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsightsResources.outputs.APPLICATIONINSIGHTS_CONNECTION_STRING
    }
  }

  resource logs 'config' = {
    name: 'logs'
    properties: {
      applicationLogs: {
        fileSystem: {
          level: 'Verbose'
        }
      }
      detailedErrorMessages: {
        enabled: true
      }
      failedRequestsTracing: {
        enabled: true
      }
      httpLogs: {
        fileSystem: {
          enabled: true
          retentionInDays: 1
          retentionInMb: 35
        }
      }
    }
  }
}

resource api 'Microsoft.Web/sites@2022-03-01' = {
  name: '${abbrs.webSitesAppService}api-${resourceToken}'
  location: location
  tags: union(tags, { 'azd-service-name': 'api' })
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      alwaysOn: true
      linuxFxVersion: 'NODE|16-lts'
      ftpsState: 'FtpsOnly'
    }
    httpsOnly: true
  }

  identity: {
    type: 'SystemAssigned'
  }

  resource appSettings 'config' = {
    name: 'appsettings'
    properties: {
      AZURE_COSMOS_CONNECTION_STRING_KEY: 'AZURE-COSMOS-CONNECTION-STRING'
      AZURE_COSMOS_DATABASE_NAME: cosmos::database.name
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
      AZURE_KEY_VAULT_ENDPOINT: keyVault.properties.vaultUri
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsightsResources.outputs.APPLICATIONINSIGHTS_CONNECTION_STRING
    }
  }

  resource logs 'config' = {
    name: 'logs'
    properties: {
      applicationLogs: {
        fileSystem: {
          level: 'Verbose'
        }
      }
      detailedErrorMessages: {
        enabled: true
      }
      failedRequestsTracing: {
        enabled: true
      }
      httpLogs: {
        fileSystem: {
          enabled: true
          retentionInDays: 1
          retentionInMb: 35
        }
      }
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: '${abbrs.keyVaultVaults}${resourceToken}'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: concat([
        {
          objectId: api.identity.principalId
          permissions: {
            secrets: [
              'get'
              'list'
            ]
          }
          tenantId: subscription().tenantId
        }
      ], !empty(principalId) ? [
        {
          objectId: principalId
          permissions: {
            secrets: [
              'get'
              'list'
            ]
          }
          tenantId: subscription().tenantId
        }
      ] : [])
  }

  resource cosmosConnectionString 'secrets' = {
    name: 'AZURE-COSMOS-CONNECTION-STRING'
    properties: {
      value: cosmos.listConnectionStrings().connectionStrings[0].connectionString
    }
  }
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2022-05-15' = {
  name: '${abbrs.documentDBDatabaseAccounts}${resourceToken}'
  kind: 'MongoDB'
  location: location
  tags: tags
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    apiProperties: {
      serverVersion: '4.0'
    }
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }

  resource database 'mongodbDatabases' = {
    name: 'Todo'
    properties: {
      resource: {
        id: 'Todo'
      }
    }

    resource list 'collections' = {
      name: 'TodoList'
      properties: {
        resource: {
          id: 'TodoList'
          shardKey: {
            _id: 'Hash'
          }
          indexes: [
            {
              key: {
                keys: [
                  '_id'
                ]
              }
            }
          ]
        }
      }
    }

    resource item 'collections' = {
      name: 'TodoItem'
      properties: {
        resource: {
          id: 'TodoItem'
          shardKey: {
            _id: 'Hash'
          }
          indexes: [
            {
              key: {
                keys: [
                  '_id'
                ]
              }
            }
          ]
        }
      }
    }
  }
}

module applicationInsightsResources 'applicationinsights.bicep' = {
  name: 'applicationinsights-resources'
  params: {
    resourceToken: resourceToken
    location: location
    tags: tags
  }
}


output AZURE_COSMOS_CONNECTION_STRING_KEY string = 'AZURE-COSMOS-CONNECTION-STRING'
output AZURE_COSMOS_DATABASE_NAME string = cosmos::database.name
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.properties.vaultUri
output APPLICATIONINSIGHTS_CONNECTION_STRING string = applicationInsightsResources.outputs.APPLICATIONINSIGHTS_CONNECTION_STRING
output WEB_URI string = 'https://${web.properties.defaultHostName}'
output API_URI string = 'https://${api.properties.defaultHostName}'
