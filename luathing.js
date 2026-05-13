const { Beautify, Minify } = require('lua-format')
const { readFile, writeFile } = require("fs").promises

;(async () => {
    const args = process.argv
    const input = args[2], output = args[3], type = args[4]

    console.log("ehh")

    const data = (await readFile(input)).toString()
    console.log("read", data)
    const fixed = type === "b" ? Beautify(data, {
        RenameVariables: false,
        RenameGlobals: false,
        SolveMath: true,
        Indentation: '    '
    }) : Minify(data, {
        RenameVariables: false,
        RenameGlobals: false,
        SolveMath: false
    })

    console.log('done', fixed)

    const source = fixed.match(/--\[\[.+--\]\]\n+(.+)/s) || [0, fixed]

    writeFile(output, source[1])
})()