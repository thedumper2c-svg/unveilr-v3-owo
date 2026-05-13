// @ts-check
const luaparse = require("luaparse")
const tab = "    "
const print = console.log

/**
 @typedef {Record<string, any>} Expression
 @property {string} type
*/

const typesToBeautify = {
    "table": true,
    "Identifier": true
}

/**
 @param {string} code
 @returns {string}
*/
const beautify = (code) => {
    const ast = luaparse.parse(code);
    const output = []
    /**
     @param {Expression} expression
     @param {number} indentLevel
     @returns {string}
    */
    const beautifyExpr = (expression, indentLevel) => {
        const type = expression.type
        const indent = tab.repeat(indentLevel)
        const nextIndent = tab.repeat(indentLevel + 1)
        /** @type {Array<string>} */
        const stats = []

        let code = ""

        switch (expression.type) {
            case "Chunk":
                for (let stat of expression.body) {
                    stats.push(beautifyExpr(stat, indentLevel + 1))
                }
                return stats.join(stats.join("\n" + tab.repeat(indentLevel + 1)))
            case "LocalStatement":
                code = "local "
                for (let variable of expression.variables) {
                    code += beautifyExpr(variable, indentLevel) + ", "
                }
                code = code.substring(0, code.length - 2)
                if(!expression.init) return code + ";"
                code += " = "
                for (let value of expression.init) {
                    code += beautifyExpr(value, 0) + ", "
                }
                return code.substring(0, code.length - 2)
            case "StringLiteral":
                return `"${expression.value.replace('"', '\\"')}"`
            case "Identifier":
                return expression.name
            case "CallExpression":
                code = beautifyExpr(expression.base, 0) + "("
                const args = []
                const argList = expression.arguments
                let doBeautify = true;

                for (let stat of argList) {
                    args.push(beautifyExpr(stat, indentLevel + 1))
                    // @ts-ignore
                    doBeautify = typesToBeautify[stat.type]
                }

                if(doBeautify) {
                    code += "\n" + nextIndent + args.join(",\n" + nextIndent) + "\n" + indent
                } else {
                    code += args.join(", ")
                }
                return code + ")";
            case "CallStatement":
                return beautifyExpr(expression.expression, indentLevel)
            case "IfStatement":
                let ifClause;
                for(let clause of expression.clauses) {
                    if(clause.type === "IfClause") {
                        ifClause = clause
                        break
                    }
                } // not sure if IfClause is always first..

                code = `if (${beautifyExpr(ifClause.condition, indentLevel + 1)}) then\n${indent}`
                ifClause.type = "Chunk"
                code += beautifyExpr(ifClause, indentLevel + 1)
                code += `\n${indent}end`
                return code;
            default:
                print(`UNSUPPORTED STATEMENT "${type}"!`)
                print(expression)
                return "???"
        }
    }
    for (let stat of ast.body) {
        output.push(beautifyExpr(stat, 0))
    }
    return output.join("\n")
}
print(beautify(require("fs").readFileSync("input.lua").toString()))
module.exports = beautify