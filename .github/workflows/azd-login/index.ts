import { getIDToken } from "@actions/core"

(async () => {
    console.log((await getIDToken()).length)
})()