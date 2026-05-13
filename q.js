/*const fs = require("fs").promises;
const path = require('path');
const { spawn, ChildProcess, execFile } = require('child_process');

const unveilrDir = path.resolve("../unveilr-v3")
const print = console.log

;(async() => {
  const file = "inputs/opwkfepowg"
  const out = "inputs/polfdaw"

  await fs.writeFile(unveilrDir + "/" + file, "print('Hi')")

  const params = [ "run", "main"]//, "main", `ipt=${file}`, `out=${out}` ]

  const start = performance.now()
  const proc = spawn("lune", params, {
    cwd: unveilrDir
  })

  proc.stdin.write('print("Hi")\n');
  proc.stdout.on("data", (a) => print(a.toString()))

  proc.on("close", (a) => {
    print("Closed!",a,performance.now()-a)
  })
})()*/
const fs = require("fs").promises
const beautify = require("./modules/lua_beautifier")

;(async()=>{
  await fs.writeFile("meow.lua", beautify((await fs.readFile("luaobf2.lua")).toString()))
})()