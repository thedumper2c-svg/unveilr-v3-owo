const fs = require('fs')
const API = "http://api.plusgiant5.com/konstant"

const decompile = async (bytecode) => {
    return await (await (fetch(API + "/decompile", {
        body: bytecode,
        method: "POST",
        headers: {
            "Content-Type": "text/plain"
        }
    }))).text()
}

decompile(fs.readFileSync("msec/a.luac")).then((a) => console.log(a))