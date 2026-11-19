targetScope = 'subscription'
param seed string = subscription().subscriptionId
output unique string = uniqueString(seed)
