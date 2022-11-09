import { getIDToken } from "@actions/core"

(async () => {
    process.stdout.write(await getIDToken("api://AzureADTokenExchange"))
})()